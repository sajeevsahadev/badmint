-- =====================================================================
-- Badmint v23 — Wallet contributions: restrict INSERT to managers/owners
-- Run once in Supabase SQL Editor
-- =====================================================================

-- Only managers and owners may add wallet contributions.
-- Players can still add wallet-paid expenses (that restriction is on paysplit_expenses, unchanged).
DROP POLICY IF EXISTS "club members add wallet" ON wallet_contributions;
CREATE POLICY "managers add wallet"
  ON wallet_contributions FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM club_members
      WHERE club_id = wallet_contributions.club_id
        AND user_id = auth.uid()
        AND role IN ('owner', 'manager')
    )
  );

-- Also enforce the same check inside the RPC (defence-in-depth).
CREATE OR REPLACE FUNCTION add_wallet_contribution(
  p_club_id        uuid,
  p_player_id      uuid,
  p_amount         numeric,
  p_notes          text         DEFAULT NULL,
  p_contributed_at timestamptz  DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid()
      AND role IN ('owner', 'manager')
  ) THEN
    RAISE EXCEPTION 'Only club managers and owners can add wallet contributions';
  END IF;

  INSERT INTO wallet_contributions (club_id, player_id, amount, notes, created_by, contributed_at)
  VALUES (p_club_id, p_player_id, p_amount, p_notes, auth.uid(), COALESCE(p_contributed_at, now()))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION add_wallet_contribution(uuid,uuid,numeric,text,timestamptz) TO authenticated;
