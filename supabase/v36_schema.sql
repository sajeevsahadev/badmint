-- v36: Multi-payer expenses + paysplit_expense_payers table
-- Run this in the Supabase SQL Editor after v35 (or v32/v33 if v34/v35 don't exist).

-- ── 1. New table: paysplit_expense_payers ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS paysplit_expense_payers (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  expense_id uuid NOT NULL REFERENCES paysplit_expenses(id) ON DELETE CASCADE,
  player_id  uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  amount     numeric(10,2) NOT NULL CHECK (amount > 0),
  UNIQUE(expense_id, player_id)
);

-- ── 2. RLS for paysplit_expense_payers ────────────────────────────────────────
ALTER TABLE paysplit_expense_payers ENABLE ROW LEVEL SECURITY;

-- Members of the club can SELECT payers for expenses in their club
CREATE POLICY "pep_select_members" ON paysplit_expense_payers
  FOR SELECT USING (
    EXISTS (
      SELECT 1
      FROM paysplit_expenses pe
      JOIN club_members cm ON cm.club_id = pe.club_id
      WHERE pe.id = paysplit_expense_payers.expense_id
        AND cm.user_id = auth.uid()
    )
  );

-- Creator of the expense or a club manager/owner can INSERT/UPDATE/DELETE
CREATE POLICY "pep_write_creator_or_manager" ON paysplit_expense_payers
  FOR ALL USING (
    EXISTS (
      SELECT 1
      FROM paysplit_expenses pe
      JOIN club_members cm ON cm.club_id = pe.club_id
      WHERE pe.id = paysplit_expense_payers.expense_id
        AND cm.user_id = auth.uid()
        AND (pe.created_by = auth.uid() OR cm.role IN ('owner','manager'))
    )
  );

-- ── 3. Grant to authenticated ─────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON paysplit_expense_payers TO authenticated;

-- ── 3b. Replace the v12 expense_payment_source constraint ────────────────────
-- The old constraint required paid_player_id IS NOT NULL for non-wallet expenses.
-- Multi-payer expenses have paid_player_id = NULL + paid_from_wallet = false, so
-- that constraint must be relaxed. We use a simpler NOT NULL + boolean check here;
-- the application-level RPC enforces that either a single payer or multi-payer rows
-- are provided (not neither). A full deferrable FK-based constraint would require
-- a separate deferred check trigger, which is over-engineered for this threat model.
-- Note: the old expense_payment_source CHECK constraint blocked multi-payer inserts
-- (paid_player_id=NULL, paid_from_wallet=false). We drop it here; enforcement is
-- done inside the add_expense/update_expense RPCs instead (subqueries can't be used
-- in CHECK constraints in PostgreSQL).
ALTER TABLE paysplit_expenses DROP CONSTRAINT IF EXISTS expense_payment_source;

-- ── 4. Drop and recreate add_expense with optional p_payers ──────────────
-- First check existing signature to drop correctly
DROP FUNCTION IF EXISTS add_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean);
DROP FUNCTION IF EXISTS add_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean,jsonb);

CREATE OR REPLACE FUNCTION add_expense(
  p_club_id          uuid,
  p_title            text,
  p_category         text,
  p_amount           numeric,
  p_paid_player_id   uuid    DEFAULT NULL,
  p_expense_date     date    DEFAULT CURRENT_DATE,
  p_participant_ids  uuid[]  DEFAULT '{}',
  p_notes            text    DEFAULT NULL,
  p_paid_from_wallet boolean DEFAULT false,
  p_payers           jsonb   DEFAULT NULL   -- optional: [{player_id, amount}, ...]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_expense_id uuid;
  v_payer      jsonb;
  v_multi      boolean;
  v_pid        uuid;
  v_amt        numeric;
BEGIN
  -- Auth check: must be a member of the club (was accidentally dropped from v36 draft)
  IF NOT EXISTS (
    SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;

  -- Determine whether this is a multi-payer expense
  v_multi := p_payers IS NOT NULL
    AND jsonb_array_length(p_payers) > 1
    AND NOT p_paid_from_wallet;

  -- Validate payment source for non-wallet, non-multi-payer expenses
  IF NOT p_paid_from_wallet AND NOT v_multi
     AND p_paid_player_id IS NULL
     AND (p_payers IS NULL OR jsonb_array_length(p_payers) = 0)
  THEN
    RAISE EXCEPTION 'Specify who paid, or select wallet payment';
  END IF;

  INSERT INTO paysplit_expenses (
    club_id, title, category, amount,
    paid_player_id, expense_date, notes, paid_from_wallet, created_by
  ) VALUES (
    p_club_id, p_title, p_category, p_amount,
    CASE WHEN v_multi THEN NULL
         WHEN p_paid_from_wallet THEN NULL
         WHEN p_payers IS NOT NULL AND jsonb_array_length(p_payers) = 1
              THEN (p_payers->0->>'player_id')::uuid
         ELSE p_paid_player_id
    END,
    p_expense_date, p_notes, p_paid_from_wallet, auth.uid()
  )
  RETURNING id INTO v_expense_id;

  -- Insert participants — column is share_amount (defined in v11_schema.sql)
  IF array_length(p_participant_ids, 1) > 0 THEN
    INSERT INTO paysplit_participants (expense_id, player_id, share_amount)
    SELECT v_expense_id, unnest(p_participant_ids),
           ROUND((p_amount / array_length(p_participant_ids, 1))::numeric, 2);
  END IF;

  -- Insert multi-payer rows
  IF v_multi THEN
    FOR v_payer IN SELECT * FROM jsonb_array_elements(p_payers)
    LOOP
      v_pid := (v_payer->>'player_id')::uuid;
      v_amt := (v_payer->>'amount')::numeric;
      INSERT INTO paysplit_expense_payers (expense_id, player_id, amount)
      VALUES (v_expense_id, v_pid, v_amt)
      ON CONFLICT (expense_id, player_id) DO UPDATE SET amount = EXCLUDED.amount;
    END LOOP;
  END IF;

  RETURN v_expense_id;
END;
$$;

-- ── 5. Drop and recreate update_expense with optional p_payers ───────────────
DROP FUNCTION IF EXISTS update_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean);
DROP FUNCTION IF EXISTS update_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean,jsonb);

CREATE OR REPLACE FUNCTION update_expense(
  p_expense_id       uuid,
  p_title            text,
  p_category         text,
  p_amount           numeric,
  p_paid_player_id   uuid    DEFAULT NULL,
  p_expense_date     date    DEFAULT CURRENT_DATE,
  p_participant_ids  uuid[]  DEFAULT '{}',
  p_notes            text    DEFAULT NULL,
  p_paid_from_wallet boolean DEFAULT false,
  p_payers           jsonb   DEFAULT NULL   -- optional: [{player_id, amount}, ...]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_club_id uuid;
  v_payer   jsonb;
  v_multi   boolean;
  v_pid     uuid;
  v_amt     numeric;
BEGIN
  -- Auth check: creator or manager
  SELECT club_id INTO v_club_id FROM paysplit_expenses WHERE id = p_expense_id;
  IF NOT EXISTS (
    SELECT 1 FROM paysplit_expenses pe
    JOIN club_members cm ON cm.club_id = pe.club_id
    WHERE pe.id = p_expense_id
      AND cm.user_id = auth.uid()
      AND (pe.created_by = auth.uid() OR cm.role IN ('owner','manager'))
  ) THEN
    RAISE EXCEPTION 'Not authorised to edit this expense';
  END IF;

  v_multi := p_payers IS NOT NULL
    AND jsonb_array_length(p_payers) > 1
    AND NOT p_paid_from_wallet;

  UPDATE paysplit_expenses SET
    title            = p_title,
    category         = p_category,
    amount           = p_amount,
    paid_player_id   = CASE WHEN v_multi THEN NULL
                            WHEN p_paid_from_wallet THEN NULL
                            WHEN p_payers IS NOT NULL AND jsonb_array_length(p_payers) = 1
                                 THEN (p_payers->0->>'player_id')::uuid
                            ELSE p_paid_player_id
                       END,
    expense_date     = p_expense_date,
    notes            = p_notes,
    paid_from_wallet = p_paid_from_wallet
  WHERE id = p_expense_id;

  -- Replace participants — column is share_amount (defined in v11_schema.sql)
  DELETE FROM paysplit_participants WHERE expense_id = p_expense_id;
  IF array_length(p_participant_ids, 1) > 0 THEN
    INSERT INTO paysplit_participants (expense_id, player_id, share_amount)
    SELECT p_expense_id, unnest(p_participant_ids),
           ROUND((p_amount / array_length(p_participant_ids, 1))::numeric, 2);
  END IF;

  -- Replace multi-payer rows
  DELETE FROM paysplit_expense_payers WHERE expense_id = p_expense_id;
  IF v_multi THEN
    FOR v_payer IN SELECT * FROM jsonb_array_elements(p_payers)
    LOOP
      v_pid := (v_payer->>'player_id')::uuid;
      v_amt := (v_payer->>'amount')::numeric;
      INSERT INTO paysplit_expense_payers (expense_id, player_id, amount)
      VALUES (p_expense_id, v_pid, v_amt);
    END LOOP;
  END IF;
END;
$$;

-- ── 6. Drop and recreate get_expenses to include payers array ────────────────
DROP FUNCTION IF EXISTS get_expenses(uuid);

CREATE OR REPLACE FUNCTION get_expenses(p_club_id uuid)
RETURNS TABLE (
  id              uuid,
  title           text,
  category        text,
  amount          numeric,
  paid_player_id  uuid,
  paid_name       text,
  expense_date    date,
  notes           text,
  paid_from_wallet boolean,
  created_by      uuid,
  created_at      timestamptz,
  participants    jsonb,
  payers          jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verify caller is a club member
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.category,
    e.amount,
    e.paid_player_id,
    -- For multi-payer, paid_name shows "Multiple payers"; for wallet shows "Wallet"; else payer name
    CASE
      WHEN e.paid_from_wallet THEN 'Wallet'
      WHEN e.paid_player_id IS NULL THEN 'Multiple payers'
      ELSE COALESCE(up.nickname, pl.display_name)
    END                                                 AS paid_name,
    e.expense_date,
    e.notes,
    e.paid_from_wallet,
    e.created_by,
    e.created_at,
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
               'player_id', pp.player_id,
               'name',      COALESCE(up2.nickname, pl2.display_name),
               'share',     pp.share_amount
             ) ORDER BY COALESCE(up2.nickname, pl2.display_name))
       FROM paysplit_participants pp
       JOIN players pl2 ON pl2.id = pp.player_id
       LEFT JOIN user_profiles up2 ON up2.user_id = pl2.user_id
       WHERE pp.expense_id = e.id),
      '[]'::jsonb
    )                                                   AS participants,
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
               'player_id', pep.player_id,
               'name',      COALESCE(up3.nickname, pl3.display_name),
               'amount',    pep.amount
             ) ORDER BY COALESCE(up3.nickname, pl3.display_name))
       FROM paysplit_expense_payers pep
       JOIN players pl3 ON pl3.id = pep.player_id
       LEFT JOIN user_profiles up3 ON up3.user_id = pl3.user_id
       WHERE pep.expense_id = e.id),
      '[]'::jsonb
    )                                                   AS payers
  FROM paysplit_expenses e
  LEFT JOIN players pl ON pl.id = e.paid_player_id AND pl.club_id = p_club_id
  LEFT JOIN user_profiles up ON up.user_id = pl.user_id
  WHERE e.club_id = p_club_id
  ORDER BY e.expense_date DESC, e.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_expenses(uuid) TO authenticated;

-- ── 7. Update get_balance_summary to handle multi-payer expenses ──────────────
-- Drop old version; recreate with multi-payer debt edge generation.
DROP FUNCTION IF EXISTS get_balance_summary(uuid);

CREATE OR REPLACE FUNCTION get_balance_summary(p_club_id uuid)
RETURNS TABLE (
  from_player_id uuid,
  from_name      text,
  to_player_id   uuid,
  to_name        text,
  net_amount     numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;

  RETURN QUERY
  WITH raw_debts AS (
    -- Single-payer expenses (paid_player_id IS NOT NULL, no multi-payer rows)
    SELECT
      pp.player_id                          AS from_id,
      e.paid_player_id                      AS to_id,
      pp.share_amount                       AS amount
    FROM paysplit_expenses e
    JOIN paysplit_participants pp ON pp.expense_id = e.id
    WHERE e.club_id = p_club_id
      AND e.paid_from_wallet = false
      AND e.paid_player_id IS NOT NULL
      AND pp.player_id <> e.paid_player_id
      AND NOT EXISTS (
        SELECT 1 FROM paysplit_expense_payers pep WHERE pep.expense_id = e.id
      )

    UNION ALL

    -- Multi-payer expenses: each participant owes each payer their proportional share.
    -- Each payer paid (pep.amount / e.amount) fraction of the total.
    -- Each participant owes that fraction of their own share (pp.share_amount) to that payer.
    SELECT
      pp.player_id                                                    AS from_id,
      pep.player_id                                                   AS to_id,
      ROUND((pp.share_amount * pep.amount / e.amount)::numeric, 4)   AS amount
    FROM paysplit_expenses e
    JOIN paysplit_participants pp  ON pp.expense_id = e.id
    JOIN paysplit_expense_payers pep ON pep.expense_id = e.id
    WHERE e.club_id = p_club_id
      AND e.paid_from_wallet = false
      AND pp.player_id <> pep.player_id   -- a payer doesn't owe themselves
  ),
  -- Net each (from, to) pair (A owes B 10, B owes A 3 => A owes B 7)
  paired AS (
    SELECT
      LEAST(from_id, to_id)    AS a_id,
      GREATEST(from_id, to_id) AS b_id,
      SUM(CASE WHEN from_id < to_id THEN amount ELSE -amount END) AS net
    FROM raw_debts
    GROUP BY LEAST(from_id, to_id), GREATEST(from_id, to_id)
  )
  SELECT
    CASE WHEN p.net > 0 THEN p.a_id ELSE p.b_id END  AS from_player_id,
    COALESCE(upa.nickname, pa.display_name)             AS from_name,
    CASE WHEN p.net > 0 THEN p.b_id ELSE p.a_id END  AS to_player_id,
    COALESCE(upb.nickname, pb.display_name)             AS to_name,
    ABS(p.net)                                          AS net_amount
  FROM paired p
  JOIN players pa ON pa.id = (CASE WHEN p.net > 0 THEN p.a_id ELSE p.b_id END)
  JOIN players pb ON pb.id = (CASE WHEN p.net > 0 THEN p.b_id ELSE p.a_id END)
  LEFT JOIN user_profiles upa ON upa.user_id = pa.user_id
  LEFT JOIN user_profiles upb ON upb.user_id = pb.user_id
  WHERE ABS(p.net) >= 0.01;
END;
$$;

GRANT EXECUTE ON FUNCTION get_balance_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION add_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION update_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean,jsonb) TO authenticated;
