-- =====================================================================
-- Badmint v11 — PaySplits: expense tracking & equal cost splitting
-- Run in Supabase SQL Editor after v10_schema.sql
-- =====================================================================

-- ── Tables ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS paysplit_expenses (
  id             uuid          DEFAULT gen_random_uuid() PRIMARY KEY,
  club_id        uuid          NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  title          text          NOT NULL,
  category       text          NOT NULL DEFAULT 'other'
                               CHECK (category IN ('facility','food','drinks','equipment','transport','tax','other')),
  amount         numeric(10,2) NOT NULL CHECK (amount > 0),
  paid_player_id uuid          NOT NULL REFERENCES players(id),
  expense_date   date          NOT NULL DEFAULT current_date,
  notes          text,
  created_by     uuid          NOT NULL REFERENCES auth.users(id),
  created_at     timestamptz   NOT NULL DEFAULT now(),
  updated_at     timestamptz   NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS paysplit_participants (
  id           uuid          DEFAULT gen_random_uuid() PRIMARY KEY,
  expense_id   uuid          NOT NULL REFERENCES paysplit_expenses(id) ON DELETE CASCADE,
  player_id    uuid          NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  share_amount numeric(10,2) NOT NULL,
  UNIQUE (expense_id, player_id)
);

CREATE TABLE IF NOT EXISTS paysplit_notes (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  club_id    uuid        NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  content    text        NOT NULL,
  created_by uuid        NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ── RLS ───────────────────────────────────────────────────────────────
ALTER TABLE paysplit_expenses     ENABLE ROW LEVEL SECURITY;
ALTER TABLE paysplit_participants  ENABLE ROW LEVEL SECURITY;
ALTER TABLE paysplit_notes        ENABLE ROW LEVEL SECURITY;

-- Any club member can read/write/edit/delete expenses
CREATE POLICY "club members select expenses"
  ON paysplit_expenses FOR SELECT USING (
    EXISTS (SELECT 1 FROM club_members WHERE club_id = paysplit_expenses.club_id AND user_id = auth.uid()));
CREATE POLICY "club members insert expenses"
  ON paysplit_expenses FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM club_members WHERE club_id = paysplit_expenses.club_id AND user_id = auth.uid()));
CREATE POLICY "club members update expenses"
  ON paysplit_expenses FOR UPDATE USING (
    EXISTS (SELECT 1 FROM club_members WHERE club_id = paysplit_expenses.club_id AND user_id = auth.uid()));
CREATE POLICY "club members delete expenses"
  ON paysplit_expenses FOR DELETE USING (
    EXISTS (SELECT 1 FROM club_members WHERE club_id = paysplit_expenses.club_id AND user_id = auth.uid()));

-- Participants managed via SECURITY DEFINER RPCs; club members can read
CREATE POLICY "club members select participants"
  ON paysplit_participants FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM paysplit_expenses e
      JOIN club_members cm ON cm.club_id = e.club_id AND cm.user_id = auth.uid()
      WHERE e.id = paysplit_participants.expense_id));

-- Notes: any member can add/delete; only creator can update content
CREATE POLICY "club members select notes"
  ON paysplit_notes FOR SELECT USING (
    EXISTS (SELECT 1 FROM club_members WHERE club_id = paysplit_notes.club_id AND user_id = auth.uid()));
CREATE POLICY "club members insert notes"
  ON paysplit_notes FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM club_members WHERE club_id = paysplit_notes.club_id AND user_id = auth.uid()));
CREATE POLICY "note creator update"
  ON paysplit_notes FOR UPDATE USING (created_by = auth.uid());
CREATE POLICY "club members delete notes"
  ON paysplit_notes FOR DELETE USING (
    EXISTS (SELECT 1 FROM club_members WHERE club_id = paysplit_notes.club_id AND user_id = auth.uid()));

-- ── RPC: add_expense ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION add_expense(
  p_club_id        uuid,
  p_title          text,
  p_category       text,
  p_amount         numeric,
  p_paid_player_id uuid,
  p_expense_date   date,
  p_participant_ids uuid[],
  p_notes          text DEFAULT NULL
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
  IF v_n IS NULL OR v_n = 0 THEN
    RAISE EXCEPTION 'At least one participant is required';
  END IF;
  v_share := ROUND(p_amount / v_n, 2);

  INSERT INTO paysplit_expenses (club_id, title, category, amount, paid_player_id, expense_date, notes, created_by)
  VALUES (p_club_id, trim(p_title), p_category, p_amount, p_paid_player_id, p_expense_date, p_notes, auth.uid())
  RETURNING id INTO v_id;

  FOREACH v_pid IN ARRAY p_participant_ids LOOP
    INSERT INTO paysplit_participants (expense_id, player_id, share_amount)
    VALUES (v_id, v_pid, v_share)
    ON CONFLICT (expense_id, player_id) DO NOTHING;
  END LOOP;

  RETURN v_id;
END;
$$;

-- ── RPC: update_expense ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_expense(
  p_expense_id     uuid,
  p_title          text,
  p_category       text,
  p_amount         numeric,
  p_paid_player_id uuid,
  p_expense_date   date,
  p_participant_ids uuid[],
  p_notes          text DEFAULT NULL
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
  ) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF v_n IS NULL OR v_n = 0 THEN RAISE EXCEPTION 'At least one participant is required'; END IF;
  v_share := ROUND(p_amount / v_n, 2);

  UPDATE paysplit_expenses
  SET title = trim(p_title), category = p_category, amount = p_amount,
      paid_player_id = p_paid_player_id, expense_date = p_expense_date,
      notes = p_notes, updated_at = now()
  WHERE id = p_expense_id;

  DELETE FROM paysplit_participants WHERE expense_id = p_expense_id;
  FOREACH v_pid IN ARRAY p_participant_ids LOOP
    INSERT INTO paysplit_participants (expense_id, player_id, share_amount)
    VALUES (p_expense_id, v_pid, v_share);
  END LOOP;
END;
$$;

-- ── RPC: delete_expense ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION delete_expense(p_expense_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM paysplit_expenses e
    JOIN club_members cm ON cm.club_id = e.club_id AND cm.user_id = auth.uid()
    WHERE e.id = p_expense_id
  ) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  DELETE FROM paysplit_expenses WHERE id = p_expense_id;
END;
$$;

-- ── RPC: get_expenses ─────────────────────────────────────────────────
-- Returns all expenses with resolved names and participants JSON
CREATE OR REPLACE FUNCTION get_expenses(p_club_id uuid)
RETURNS TABLE(
  id             uuid,
  title          text,
  category       text,
  amount         numeric,
  expense_date   date,
  notes          text,
  created_by     uuid,
  created_at     timestamptz,
  paid_player_id uuid,
  paid_name      text,
  participants   jsonb
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    e.id, e.title, e.category, e.amount, e.expense_date, e.notes,
    e.created_by, e.created_at, e.paid_player_id,
    COALESCE(pup.nickname, pp.display_name) AS paid_name,
    COALESCE(
      jsonb_agg(jsonb_build_object(
        'player_id', pa.player_id,
        'name',      COALESCE(aup.nickname, ap.display_name),
        'share',     pa.share_amount
      )) FILTER (WHERE pa.player_id IS NOT NULL),
      '[]'::jsonb
    ) AS participants
  FROM paysplit_expenses e
  JOIN players pp ON pp.id = e.paid_player_id
  LEFT JOIN user_profiles pup ON pup.user_id = pp.user_id
  LEFT JOIN paysplit_participants pa ON pa.expense_id = e.id
  LEFT JOIN players ap ON ap.id = pa.player_id
  LEFT JOIN user_profiles aup ON aup.user_id = ap.user_id
  WHERE e.club_id = p_club_id
    AND EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
  GROUP BY e.id, e.title, e.category, e.amount, e.expense_date, e.notes,
           e.created_by, e.created_at, e.paid_player_id, pup.nickname, pp.display_name
  ORDER BY e.expense_date DESC, e.created_at DESC;
$$;

-- ── RPC: get_balance_summary ──────────────────────────────────────────
-- Pairwise net balances: from_player_id owes to_player_id net_amount AED.
-- Logic: non-payee participants owe the payee their share per expense.
-- Pairs are netted so only the net direction shows.
CREATE OR REPLACE FUNCTION get_balance_summary(p_club_id uuid)
RETURNS TABLE(
  from_player_id uuid,
  from_name      text,
  to_player_id   uuid,
  to_name        text,
  net_amount     numeric
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH raw AS (
    SELECT
      pa.player_id     AS debtor,
      e.paid_player_id AS creditor,
      pa.share_amount  AS amt
    FROM paysplit_expenses e
    JOIN paysplit_participants pa ON pa.expense_id = e.id
    WHERE e.club_id = p_club_id
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
    CASE WHEN n.net > 0 THEN n.p_lo ELSE n.p_hi END AS from_player_id,
    CASE WHEN n.net > 0 THEN COALESCE(up_lo.nickname, p_lo.display_name)
                         ELSE COALESCE(up_hi.nickname, p_hi.display_name) END AS from_name,
    CASE WHEN n.net > 0 THEN n.p_hi ELSE n.p_lo END AS to_player_id,
    CASE WHEN n.net > 0 THEN COALESCE(up_hi.nickname, p_hi.display_name)
                         ELSE COALESCE(up_lo.nickname, p_lo.display_name) END AS to_name,
    ABS(n.net) AS net_amount
  FROM netted n
  JOIN players p_lo ON p_lo.id = n.p_lo
  JOIN players p_hi ON p_hi.id = n.p_hi
  LEFT JOIN user_profiles up_lo ON up_lo.user_id = p_lo.user_id
  LEFT JOIN user_profiles up_hi ON up_hi.user_id = p_hi.user_id
  WHERE EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
  ORDER BY ABS(n.net) DESC;
$$;

GRANT EXECUTE ON FUNCTION add_expense(uuid,text,text,numeric,uuid,date,uuid[],text)    TO authenticated;
GRANT EXECUTE ON FUNCTION update_expense(uuid,text,text,numeric,uuid,date,uuid[],text) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_expense(uuid)                                          TO authenticated;
GRANT EXECUTE ON FUNCTION get_expenses(uuid)                                            TO authenticated;
GRANT EXECUTE ON FUNCTION get_balance_summary(uuid)                                     TO authenticated;
