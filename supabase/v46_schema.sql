-- =====================================================================
-- Badminton 360 v46 — PaySplits: exact share splitting (no fils leakage)
-- Run in Supabase SQL Editor (after v45_schema.sql)
--
-- Problem: add_expense / update_expense (last defined in v36) stored every
-- participant's share as ROUND(amount / n, 2). The rounded shares do not
-- sum back to the bill: e.g. AED 24.50 split 11 ways → 11 × 2.23 = 24.53,
-- inventing 3 fils; other amounts round down and destroy fils. These
-- leaks flow into get_balance_summary and walletNets, causing the
-- permanent small drift vs. Splitwise (which hands out 2.23 to some and
-- 2.22 to others so shares sum exactly).
--
-- Fix: split in integer fils — base = floor(total_fils / n), then give
-- the leftover (total_fils % n) fils to the first participants, one fils
-- each. SUM(share_amount) = amount, always, to the fils.
--
-- Also included: a one-time repair that re-normalises share_amount on all
-- EXISTING equal-split expenses using the same algorithm (extra fils go
-- to participants in player_id order, deterministically).
-- =====================================================================

-- ── 1. add_expense with exact splitting ──────────────────────────────
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
  v_n          int;
  v_total_fils bigint;
  v_base_fils  bigint;
  v_extra_fils bigint;
BEGIN
  -- Auth check: must be a member of the club
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
    p_club_id, trim(p_title), p_category, p_amount,
    CASE WHEN v_multi THEN NULL
         WHEN p_paid_from_wallet THEN NULL
         WHEN p_payers IS NOT NULL AND jsonb_array_length(p_payers) = 1
              THEN (p_payers->0->>'player_id')::uuid
         ELSE p_paid_player_id
    END,
    p_expense_date, p_notes, p_paid_from_wallet, auth.uid()
  )
  RETURNING id INTO v_expense_id;

  -- Insert participants with EXACT splitting in integer fils:
  -- base = floor(total_fils / n); the leftover (total_fils % n) fils are
  -- handed out +0.01 each to the first participants (array order).
  -- Guarantees SUM(share_amount) = p_amount exactly.
  v_n := COALESCE(array_length(p_participant_ids, 1), 0);
  IF v_n > 0 THEN
    v_total_fils := ROUND(p_amount * 100);
    v_base_fils  := v_total_fils / v_n;   -- integer division
    v_extra_fils := v_total_fils % v_n;

    INSERT INTO paysplit_participants (expense_id, player_id, share_amount)
    SELECT v_expense_id, t.pid,
           (v_base_fils + CASE WHEN t.ord <= v_extra_fils THEN 1 ELSE 0 END) / 100.0
    FROM unnest(p_participant_ids) WITH ORDINALITY AS t(pid, ord);
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

-- ── 2. update_expense with exact splitting ───────────────────────────
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
  v_club_id    uuid;
  v_payer      jsonb;
  v_multi      boolean;
  v_pid        uuid;
  v_amt        numeric;
  v_n          int;
  v_total_fils bigint;
  v_base_fils  bigint;
  v_extra_fils bigint;
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
    title            = trim(p_title),
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
    paid_from_wallet = p_paid_from_wallet,
    updated_at       = now()
  WHERE id = p_expense_id;

  -- Replace participants with EXACT splitting (same algorithm as add_expense)
  DELETE FROM paysplit_participants WHERE expense_id = p_expense_id;
  v_n := COALESCE(array_length(p_participant_ids, 1), 0);
  IF v_n > 0 THEN
    v_total_fils := ROUND(p_amount * 100);
    v_base_fils  := v_total_fils / v_n;
    v_extra_fils := v_total_fils % v_n;

    INSERT INTO paysplit_participants (expense_id, player_id, share_amount)
    SELECT p_expense_id, t.pid,
           (v_base_fils + CASE WHEN t.ord <= v_extra_fils THEN 1 ELSE 0 END) / 100.0
    FROM unnest(p_participant_ids) WITH ORDINALITY AS t(pid, ord);
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

GRANT EXECUTE ON FUNCTION add_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean,jsonb)    TO authenticated;
GRANT EXECUTE ON FUNCTION update_expense(uuid,text,text,numeric,uuid,date,uuid[],text,boolean,jsonb) TO authenticated;

-- ── 3. One-time repair of existing share rows ────────────────────────
-- Re-normalises every existing expense's shares with the same fils
-- algorithm. All expenses to date are equal splits, so this is safe.
-- Extra fils are assigned in player_id order (deterministic re-runs).
WITH ranked AS (
  SELECT pp.expense_id,
         pp.player_id,
         ROUND(e.amount * 100)::bigint AS total_fils,
         COUNT(*)     OVER (PARTITION BY pp.expense_id) AS n,
         ROW_NUMBER() OVER (PARTITION BY pp.expense_id ORDER BY pp.player_id) AS ord
  FROM paysplit_participants pp
  JOIN paysplit_expenses e ON e.id = pp.expense_id
),
calc AS (
  SELECT expense_id, player_id,
         ((total_fils / n) + CASE WHEN ord <= (total_fils % n) THEN 1 ELSE 0 END) / 100.0 AS new_share
  FROM ranked
)
UPDATE paysplit_participants pp
SET share_amount = c.new_share
FROM calc c
WHERE pp.expense_id = c.expense_id
  AND pp.player_id  = c.player_id
  AND pp.share_amount IS DISTINCT FROM c.new_share;

-- ── 4. Verification (run after; expect zero rows) ────────────────────
-- SELECT e.id, e.title, e.amount, SUM(pp.share_amount) AS sum_shares
-- FROM paysplit_expenses e
-- JOIN paysplit_participants pp ON pp.expense_id = e.id
-- GROUP BY e.id, e.title, e.amount
-- HAVING SUM(pp.share_amount) <> e.amount;
