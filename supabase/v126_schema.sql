-- =====================================================================
-- Badminton 360 v126 — PaySplits "Settle up"
-- Applied to prod via Supabase MCP; archived here for rebuild parity.
--
-- Record an out-of-system payment P (payer) -> Q (payee) that clears that
-- payable. Folded into get_balance_summary as a REVERSE debt edge (Q owes P),
-- which offsets "P owes Q". Both the Simplify and As-recorded balance views
-- derive from get_balance_summary, so both update automatically. Partial
-- payments leave the remainder; overpayment reverses the balance.
-- =====================================================================

CREATE TABLE IF NOT EXISTS paysplit_settlements (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id        uuid NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  from_player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,  -- payer
  to_player_id   uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,  -- payee
  amount         numeric NOT NULL CHECK (amount > 0),
  note           text,
  created_by     uuid REFERENCES auth.users(id),
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_paysplit_settlements_club ON paysplit_settlements(club_id, created_at DESC);
ALTER TABLE paysplit_settlements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ps_settle_read ON paysplit_settlements;
CREATE POLICY ps_settle_read ON paysplit_settlements FOR SELECT USING (is_member(club_id));

CREATE OR REPLACE FUNCTION add_settlement(
  p_club_id uuid, p_from_player_id uuid, p_to_player_id uuid, p_amount numeric, p_note text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  IF p_from_player_id = p_to_player_id THEN RAISE EXCEPTION 'Payer and payee must differ'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_from_player_id AND club_id = p_club_id)
     OR NOT EXISTS (SELECT 1 FROM players WHERE id = p_to_player_id AND club_id = p_club_id) THEN
    RAISE EXCEPTION 'Players must belong to this club';
  END IF;
  INSERT INTO paysplit_settlements (club_id, from_player_id, to_player_id, amount, note, created_by)
  VALUES (p_club_id, p_from_player_id, p_to_player_id, round(p_amount, 2), nullif(trim(p_note), ''), auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;
GRANT EXECUTE ON FUNCTION add_settlement(uuid,uuid,uuid,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION get_settlements(p_club_id uuid)
RETURNS TABLE(id uuid, from_player_id uuid, from_name text, to_player_id uuid, to_name text,
              amount numeric, note text, created_at timestamptz, created_by uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  RETURN QUERY
  SELECT s.id, s.from_player_id, COALESCE(upf.nickname, pf.display_name),
         s.to_player_id, COALESCE(upt.nickname, pt.display_name),
         s.amount, s.note, s.created_at, s.created_by
  FROM paysplit_settlements s
  JOIN players pf ON pf.id = s.from_player_id
  JOIN players pt ON pt.id = s.to_player_id
  LEFT JOIN user_profiles upf ON upf.user_id = pf.user_id
  LEFT JOIN user_profiles upt ON upt.user_id = pt.user_id
  WHERE s.club_id = p_club_id
  ORDER BY s.created_at DESC;
END; $$;
GRANT EXECUTE ON FUNCTION get_settlements(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION delete_settlement(p_settlement_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club uuid; v_creator uuid;
BEGIN
  SELECT club_id, created_by INTO v_club, v_creator FROM paysplit_settlements WHERE id = p_settlement_id;
  IF v_club IS NULL THEN RAISE EXCEPTION 'Settlement not found'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM club_members WHERE club_id = v_club AND user_id = auth.uid()
      AND (v_creator = auth.uid() OR role IN ('owner','manager'))
  ) THEN RAISE EXCEPTION 'Not authorised to delete this settlement'; END IF;
  DELETE FROM paysplit_settlements WHERE id = p_settlement_id;
END; $$;
GRANT EXECUTE ON FUNCTION delete_settlement(uuid) TO authenticated;

-- get_balance_summary: unchanged except the new settlements UNION branch.
CREATE OR REPLACE FUNCTION get_balance_summary(p_club_id uuid)
RETURNS TABLE (from_player_id uuid, from_name text, to_player_id uuid, to_name text, net_amount numeric)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  RETURN QUERY
  WITH raw_debts AS (
    SELECT pp.player_id AS from_id, e.paid_player_id AS to_id, pp.share_amount AS amount
    FROM paysplit_expenses e JOIN paysplit_participants pp ON pp.expense_id = e.id
    WHERE e.club_id = p_club_id AND e.paid_from_wallet = false AND e.paid_player_id IS NOT NULL
      AND pp.player_id <> e.paid_player_id
      AND NOT EXISTS (SELECT 1 FROM paysplit_expense_payers pep WHERE pep.expense_id = e.id)
    UNION ALL
    SELECT pp.player_id, pep.player_id, ROUND((pp.share_amount * pep.amount / e.amount)::numeric, 4)
    FROM paysplit_expenses e JOIN paysplit_participants pp ON pp.expense_id = e.id
    JOIN paysplit_expense_payers pep ON pep.expense_id = e.id
    WHERE e.club_id = p_club_id AND e.paid_from_wallet = false AND pp.player_id <> pep.player_id
    UNION ALL
    -- Settlements: payment P->Q reduces "P owes Q" => reverse edge "Q owes P".
    SELECT s.to_player_id, s.from_player_id, s.amount
    FROM paysplit_settlements s WHERE s.club_id = p_club_id
  ),
  paired AS (
    SELECT LEAST(from_id, to_id) AS a_id, GREATEST(from_id, to_id) AS b_id,
           SUM(CASE WHEN from_id < to_id THEN amount ELSE -amount END) AS net
    FROM raw_debts GROUP BY LEAST(from_id, to_id), GREATEST(from_id, to_id)
  )
  SELECT
    CASE WHEN p.net > 0 THEN p.a_id ELSE p.b_id END, COALESCE(upa.nickname, pa.display_name),
    CASE WHEN p.net > 0 THEN p.b_id ELSE p.a_id END, COALESCE(upb.nickname, pb.display_name), ABS(p.net)
  FROM paired p
  JOIN players pa ON pa.id = (CASE WHEN p.net > 0 THEN p.a_id ELSE p.b_id END)
  JOIN players pb ON pb.id = (CASE WHEN p.net > 0 THEN p.b_id ELSE p.a_id END)
  LEFT JOIN user_profiles upa ON upa.user_id = pa.user_id
  LEFT JOIN user_profiles upb ON upb.user_id = pb.user_id
  WHERE ABS(p.net) >= 0.01;
END; $$;
GRANT EXECUTE ON FUNCTION get_balance_summary(uuid) TO authenticated;
