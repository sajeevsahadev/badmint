-- =====================================================================
-- Badmint v12 — Wallet: shared expense pool with FIFO contribution queue
-- Run in Supabase SQL Editor after v11_schema.sql
-- =====================================================================

-- ── Alter paysplit_expenses: support wallet payments ──────────────────
ALTER TABLE paysplit_expenses ALTER COLUMN paid_player_id DROP NOT NULL;
ALTER TABLE paysplit_expenses ADD COLUMN IF NOT EXISTS paid_from_wallet boolean NOT NULL DEFAULT false;
ALTER TABLE paysplit_expenses ADD CONSTRAINT expense_payment_source
  CHECK (paid_from_wallet = true OR paid_player_id IS NOT NULL);

-- ── Wallet contributions table ─────────────────────────────────────────
-- contributed_at determines FIFO queue position (oldest = consumed first)
CREATE TABLE IF NOT EXISTS wallet_contributions (
  id             uuid          DEFAULT gen_random_uuid() PRIMARY KEY,
  club_id        uuid          NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  player_id      uuid          NOT NULL REFERENCES players(id),
  amount         numeric(10,2) NOT NULL CHECK (amount > 0),
  notes          text,
  created_by     uuid          NOT NULL REFERENCES auth.users(id),
  contributed_at timestamptz   NOT NULL DEFAULT now(),
  created_at     timestamptz   NOT NULL DEFAULT now()
);

-- ── Fix paysplit_expenses permissions: creator or manager only ─────────
DROP POLICY IF EXISTS "club members update expenses" ON paysplit_expenses;
DROP POLICY IF EXISTS "club members delete expenses" ON paysplit_expenses;

CREATE POLICY "creator or manager update expenses" ON paysplit_expenses FOR UPDATE USING (
  created_by = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members WHERE club_id = paysplit_expenses.club_id
    AND user_id = auth.uid() AND role IN ('owner','manager')));

CREATE POLICY "creator or manager delete expenses" ON paysplit_expenses FOR DELETE USING (
  created_by = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members WHERE club_id = paysplit_expenses.club_id
    AND user_id = auth.uid() AND role IN ('owner','manager')));

-- ── Fix paysplit_notes delete: creator or manager only ─────────────────
DROP POLICY IF EXISTS "club members delete notes" ON paysplit_notes;
CREATE POLICY "creator or manager delete notes" ON paysplit_notes FOR DELETE USING (
  created_by = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members WHERE club_id = paysplit_notes.club_id
    AND user_id = auth.uid() AND role IN ('owner','manager')));

-- ── Wallet contributions RLS ───────────────────────────────────────────
ALTER TABLE wallet_contributions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "club members read wallet"
  ON wallet_contributions FOR SELECT USING (
    EXISTS (SELECT 1 FROM club_members WHERE club_id = wallet_contributions.club_id AND user_id = auth.uid()));
CREATE POLICY "club members add wallet"
  ON wallet_contributions FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM club_members WHERE club_id = wallet_contributions.club_id AND user_id = auth.uid()));
CREATE POLICY "creator or manager edit wallet"
  ON wallet_contributions FOR UPDATE USING (
    created_by = auth.uid() OR EXISTS (
      SELECT 1 FROM club_members WHERE club_id = wallet_contributions.club_id
      AND user_id = auth.uid() AND role IN ('owner','manager')));
CREATE POLICY "creator or manager del wallet"
  ON wallet_contributions FOR DELETE USING (
    created_by = auth.uid() OR EXISTS (
      SELECT 1 FROM club_members WHERE club_id = wallet_contributions.club_id
      AND user_id = auth.uid() AND role IN ('owner','manager')));

-- ── RPC: add_expense (updated — wallet support + strict permissions) ───
CREATE OR REPLACE FUNCTION add_expense(
  p_club_id          uuid,
  p_title            text,
  p_category         text,
  p_amount           numeric,
  p_paid_player_id   uuid,
  p_expense_date     date,
  p_participant_ids  uuid[],
  p_notes            text    DEFAULT NULL,
  p_paid_from_wallet boolean DEFAULT false
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id    uuid;
  v_n     int := array_length(p_participant_ids, 1);
  v_share numeric;
  v_pid   uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  IF v_n IS NULL OR v_n = 0 THEN RAISE EXCEPTION 'At least one participant is required'; END IF;
  IF NOT p_paid_from_wallet AND p_paid_player_id IS NULL THEN
    RAISE EXCEPTION 'Specify who paid, or select wallet payment';
  END IF;
  v_share := ROUND(p_amount / v_n, 2);

  INSERT INTO paysplit_expenses
    (club_id, title, category, amount, paid_player_id, paid_from_wallet, expense_date, notes, created_by)
  VALUES
    (p_club_id, trim(p_title), p_category, p_amount,
     CASE WHEN p_paid_from_wallet THEN NULL ELSE p_paid_player_id END,
     p_paid_from_wallet, p_expense_date, p_notes, auth.uid())
  RETURNING id INTO v_id;

  FOREACH v_pid IN ARRAY p_participant_ids LOOP
    INSERT INTO paysplit_participants (expense_id, player_id, share_amount)
    VALUES (v_id, v_pid, v_share)
    ON CONFLICT (expense_id, player_id) DO NOTHING;
  END LOOP;

  RETURN v_id;
END;
$$;

-- ── RPC: update_expense (updated — wallet support + strict permissions) ─
CREATE OR REPLACE FUNCTION update_expense(
  p_expense_id       uuid,
  p_title            text,
  p_category         text,
  p_amount           numeric,
  p_paid_player_id   uuid,
  p_expense_date     date,
  p_participant_ids  uuid[],
  p_notes            text    DEFAULT NULL,
  p_paid_from_wallet boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_n     int := array_length(p_participant_ids, 1);
  v_share numeric;
  v_pid   uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM paysplit_expenses e
    JOIN club_members cm ON cm.club_id = e.club_id AND cm.user_id = auth.uid()
    WHERE e.id = p_expense_id
      AND (e.created_by = auth.uid() OR cm.role IN ('owner','manager'))
  ) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF v_n IS NULL OR v_n = 0 THEN RAISE EXCEPTION 'At least one participant required'; END IF;
  IF NOT p_paid_from_wallet AND p_paid_player_id IS NULL THEN
    RAISE EXCEPTION 'Specify who paid, or select wallet payment';
  END IF;
  v_share := ROUND(p_amount / v_n, 2);

  UPDATE paysplit_expenses
  SET title = trim(p_title), category = p_category, amount = p_amount,
      paid_player_id   = CASE WHEN p_paid_from_wallet THEN NULL ELSE p_paid_player_id END,
      paid_from_wallet = p_paid_from_wallet,
      expense_date = p_expense_date, notes = p_notes, updated_at = now()
  WHERE id = p_expense_id;

  DELETE FROM paysplit_participants WHERE expense_id = p_expense_id;
  FOREACH v_pid IN ARRAY p_participant_ids LOOP
    INSERT INTO paysplit_participants (expense_id, player_id, share_amount) VALUES (p_expense_id, v_pid, v_share);
  END LOOP;
END;
$$;

-- ── RPC: delete_expense (strict: creator or manager) ──────────────────
CREATE OR REPLACE FUNCTION delete_expense(p_expense_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM paysplit_expenses e
    JOIN club_members cm ON cm.club_id = e.club_id AND cm.user_id = auth.uid()
    WHERE e.id = p_expense_id
      AND (e.created_by = auth.uid() OR cm.role IN ('owner','manager'))
  ) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  DELETE FROM paysplit_expenses WHERE id = p_expense_id;
END;
$$;

-- ── RPC: get_expenses (updated — returns paid_from_wallet) ─────────────
CREATE OR REPLACE FUNCTION get_expenses(p_club_id uuid)
RETURNS TABLE(
  id               uuid,
  title            text,
  category         text,
  amount           numeric,
  expense_date     date,
  notes            text,
  created_by       uuid,
  created_at       timestamptz,
  paid_player_id   uuid,
  paid_from_wallet boolean,
  paid_name        text,
  participants     jsonb
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    e.id, e.title, e.category, e.amount, e.expense_date, e.notes,
    e.created_by, e.created_at, e.paid_player_id, e.paid_from_wallet,
    CASE WHEN e.paid_from_wallet THEN 'Wallet'
         ELSE COALESCE(pup.nickname, pp.display_name)
    END AS paid_name,
    COALESCE(
      jsonb_agg(jsonb_build_object(
        'player_id', pa.player_id,
        'name',      COALESCE(aup.nickname, ap.display_name),
        'share',     pa.share_amount
      )) FILTER (WHERE pa.player_id IS NOT NULL),
      '[]'::jsonb
    ) AS participants
  FROM paysplit_expenses e
  LEFT JOIN players pp        ON pp.id = e.paid_player_id
  LEFT JOIN user_profiles pup ON pup.user_id = pp.user_id
  LEFT JOIN paysplit_participants pa ON pa.expense_id = e.id
  LEFT JOIN players ap        ON ap.id = pa.player_id
  LEFT JOIN user_profiles aup ON aup.user_id = ap.user_id
  WHERE e.club_id = p_club_id
    AND EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
  GROUP BY e.id, e.title, e.category, e.amount, e.expense_date, e.notes,
           e.created_by, e.created_at, e.paid_player_id, e.paid_from_wallet, pup.nickname, pp.display_name
  ORDER BY e.expense_date DESC, e.created_at DESC;
$$;

-- ── RPC: get_balance_summary (updated — excludes wallet expenses) ──────
CREATE OR REPLACE FUNCTION get_balance_summary(p_club_id uuid)
RETURNS TABLE(
  from_player_id uuid,
  from_name      text,
  to_player_id   uuid,
  to_name        text,
  net_amount     numeric
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH raw AS (
    SELECT pa.player_id AS debtor, e.paid_player_id AS creditor, pa.share_amount AS amt
    FROM paysplit_expenses e
    JOIN paysplit_participants pa ON pa.expense_id = e.id
    WHERE e.club_id = p_club_id
      AND e.paid_from_wallet = false
      AND pa.player_id <> e.paid_player_id
  ),
  netted AS (
    SELECT
      LEAST(debtor, creditor)    AS p_lo,
      GREATEST(debtor, creditor) AS p_hi,
      SUM(CASE WHEN debtor < creditor THEN amt ELSE -amt END) AS net
    FROM raw
    GROUP BY LEAST(debtor, creditor), GREATEST(debtor, creditor)
    HAVING ABS(SUM(CASE WHEN debtor < creditor THEN amt ELSE -amt END)) >= 0.01
  )
  SELECT
    CASE WHEN n.net > 0 THEN n.p_lo ELSE n.p_hi END,
    CASE WHEN n.net > 0 THEN COALESCE(up_lo.nickname, p_lo.display_name)
                         ELSE COALESCE(up_hi.nickname, p_hi.display_name) END,
    CASE WHEN n.net > 0 THEN n.p_hi ELSE n.p_lo END,
    CASE WHEN n.net > 0 THEN COALESCE(up_hi.nickname, p_hi.display_name)
                         ELSE COALESCE(up_lo.nickname, p_lo.display_name) END,
    ABS(n.net)
  FROM netted n
  JOIN players p_lo ON p_lo.id = n.p_lo
  JOIN players p_hi ON p_hi.id = n.p_hi
  LEFT JOIN user_profiles up_lo ON up_lo.user_id = p_lo.user_id
  LEFT JOIN user_profiles up_hi ON up_hi.user_id = p_hi.user_id
  WHERE EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
  ORDER BY ABS(n.net) DESC;
$$;

-- ── RPC: add_wallet_contribution ──────────────────────────────────────
CREATE OR REPLACE FUNCTION add_wallet_contribution(
  p_club_id      uuid,
  p_player_id    uuid,
  p_amount       numeric,
  p_notes        text        DEFAULT NULL,
  p_contributed_at timestamptz DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a club member';
  END IF;
  INSERT INTO wallet_contributions (club_id, player_id, amount, notes, created_by, contributed_at)
  VALUES (p_club_id, p_player_id, p_amount, p_notes, auth.uid(), COALESCE(p_contributed_at, now()))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ── RPC: update_wallet_contribution ───────────────────────────────────
CREATE OR REPLACE FUNCTION update_wallet_contribution(
  p_id              uuid,
  p_amount          numeric,
  p_notes           text        DEFAULT NULL,
  p_contributed_at  timestamptz DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM wallet_contributions wc
    JOIN club_members cm ON cm.club_id = wc.club_id
    WHERE wc.id = p_id AND cm.user_id = auth.uid()
      AND (wc.created_by = auth.uid() OR cm.role IN ('owner','manager'))
  ) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  UPDATE wallet_contributions
  SET amount         = p_amount,
      notes          = p_notes,
      contributed_at = COALESCE(p_contributed_at, contributed_at)
  WHERE id = p_id;
END;
$$;

-- ── RPC: delete_wallet_contribution ───────────────────────────────────
CREATE OR REPLACE FUNCTION delete_wallet_contribution(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM wallet_contributions wc
    JOIN club_members cm ON cm.club_id = wc.club_id
    WHERE wc.id = p_id AND cm.user_id = auth.uid()
      AND (wc.created_by = auth.uid() OR cm.role IN ('owner','manager'))
  ) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  DELETE FROM wallet_contributions WHERE id = p_id;
END;
$$;

-- ── RPC: get_wallet_data ──────────────────────────────────────────────
-- Returns contributions (FIFO-ordered) + wallet-paid expenses + per-player balances.
-- Frontend computes FIFO allocation from these two lists.
CREATE OR REPLACE FUNCTION get_wallet_data(p_club_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(

    -- Contributions ordered oldest-first (FIFO queue)
    'contributions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',             wc.id,
        'player_id',      wc.player_id,
        'player_name',    COALESCE(up.nickname, p.display_name),
        'amount',         wc.amount,
        'notes',          wc.notes,
        'contributed_at', wc.contributed_at,
        'created_by',     wc.created_by
      ) ORDER BY wc.contributed_at)
      FROM wallet_contributions wc
      JOIN players p ON p.id = wc.player_id
      LEFT JOIN user_profiles up ON up.user_id = p.user_id
      WHERE wc.club_id = p_club_id
    ), '[]'::jsonb),

    -- Wallet-paid expenses ordered chronologically (for FIFO deduction order)
    'wallet_expenses', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',           e.id,
        'title',        e.title,
        'amount',       e.amount,
        'expense_date', e.expense_date,
        'created_at',   e.created_at
      ) ORDER BY e.expense_date, e.created_at)
      FROM paysplit_expenses e
      WHERE e.club_id = p_club_id AND e.paid_from_wallet = true
    ), '[]'::jsonb),

    -- Per-player wallet position (contributed vs consumed from wallet expenses)
    'player_balances', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'player_id',    b.player_id,
        'player_name',  b.player_name,
        'contributed',  b.contributed,
        'expense_share', b.expense_share,
        'balance',      b.contributed - b.expense_share
      ) ORDER BY (b.contributed - b.expense_share) DESC)
      FROM (
        SELECT
          p.id                                    AS player_id,
          COALESCE(up.nickname, p.display_name)   AS player_name,
          COALESCE(c.total, 0)                    AS contributed,
          COALESCE(s.total, 0)                    AS expense_share
        FROM players p
        LEFT JOIN user_profiles up ON up.user_id = p.user_id
        LEFT JOIN (
          SELECT player_id, SUM(amount) AS total
          FROM wallet_contributions WHERE club_id = p_club_id GROUP BY player_id
        ) c ON c.player_id = p.id
        LEFT JOIN (
          SELECT pa.player_id, SUM(pa.share_amount) AS total
          FROM paysplit_participants pa
          JOIN paysplit_expenses e ON e.id = pa.expense_id
          WHERE e.club_id = p_club_id AND e.paid_from_wallet = true
          GROUP BY pa.player_id
        ) s ON s.player_id = p.id
        WHERE p.club_id = p_club_id
          AND (c.player_id IS NOT NULL OR s.player_id IS NOT NULL)
      ) b
    ), '[]'::jsonb)

  );
END;
$$;

GRANT EXECUTE ON FUNCTION add_wallet_contribution(uuid,uuid,numeric,text,timestamptz)    TO authenticated;
GRANT EXECUTE ON FUNCTION update_wallet_contribution(uuid,numeric,text,timestamptz)       TO authenticated;
GRANT EXECUTE ON FUNCTION delete_wallet_contribution(uuid)                                TO authenticated;
GRANT EXECUTE ON FUNCTION get_wallet_data(uuid)                                           TO authenticated;
GRANT EXECUTE ON FUNCTION add_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean)    TO authenticated;
GRANT EXECUTE ON FUNCTION update_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_expense(uuid)                                            TO authenticated;
GRANT EXECUTE ON FUNCTION get_expenses(uuid)                                              TO authenticated;
GRANT EXECUTE ON FUNCTION get_balance_summary(uuid)                                       TO authenticated;
