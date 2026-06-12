-- =====================================================================
-- Badminton 360 v19 — PaySplits: per-player opening balances
-- Run in Supabase SQL Editor after v18_schema.sql
--
-- Lets a club admin record each player's starting balance when the club
-- migrates from another expense app (Splitwise etc.).
--   amount > 0  → the player should GET BACK that much from the group
--   amount < 0  → the player OWES that much to the group
-- One entry per player per club (UNIQUE) — admins can correct or remove it.
-- The frontend folds these into the settle-up netting.
-- =====================================================================

CREATE TABLE IF NOT EXISTS paysplit_opening_balances (
  id         uuid          DEFAULT gen_random_uuid() PRIMARY KEY,
  club_id    uuid          NOT NULL REFERENCES clubs(id)   ON DELETE CASCADE,
  player_id  uuid          NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  amount     numeric(10,2) NOT NULL CHECK (amount <> 0),
  notes      text,
  created_by uuid          NOT NULL REFERENCES auth.users(id),
  created_at timestamptz   NOT NULL DEFAULT now(),
  updated_at timestamptz   NOT NULL DEFAULT now(),
  UNIQUE (club_id, player_id)
);

ALTER TABLE paysplit_opening_balances ENABLE ROW LEVEL SECURITY;

-- Any club member can read; ALL writes go through the manager-only RPCs below
DROP POLICY IF EXISTS "club members read opening balances" ON paysplit_opening_balances;
CREATE POLICY "club members read opening balances"
  ON paysplit_opening_balances FOR SELECT USING (
    EXISTS (SELECT 1 FROM club_members
            WHERE club_id = paysplit_opening_balances.club_id AND user_id = auth.uid()));

-- ── RPC: set_opening_balance (insert or correct; manager/owner only) ──
CREATE OR REPLACE FUNCTION set_opening_balance(
  p_club_id   uuid,
  p_player_id uuid,
  p_amount    numeric,
  p_notes     text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  ) THEN
    RAISE EXCEPTION 'Only the club owner or a manager can set opening balances';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id AND club_id = p_club_id) THEN
    RAISE EXCEPTION 'Player does not belong to this club';
  END IF;

  -- Setting the balance to (near) zero removes the entry
  IF ABS(COALESCE(p_amount, 0)) < 0.01 THEN
    DELETE FROM paysplit_opening_balances
    WHERE club_id = p_club_id AND player_id = p_player_id;
    RETURN;
  END IF;

  INSERT INTO paysplit_opening_balances (club_id, player_id, amount, notes, created_by)
  VALUES (p_club_id, p_player_id, ROUND(p_amount, 2), NULLIF(trim(p_notes), ''), auth.uid())
  ON CONFLICT (club_id, player_id)
  DO UPDATE SET amount     = ROUND(p_amount, 2),
                notes      = NULLIF(trim(p_notes), ''),
                updated_at = now();
END;
$$;

-- ── RPC: delete_opening_balance (manager/owner only) ──────────────────
CREATE OR REPLACE FUNCTION delete_opening_balance(
  p_club_id   uuid,
  p_player_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  ) THEN
    RAISE EXCEPTION 'Only the club owner or a manager can delete opening balances';
  END IF;

  DELETE FROM paysplit_opening_balances
  WHERE club_id = p_club_id AND player_id = p_player_id;
END;
$$;

-- ── RPC: get_opening_balances (any club member) ───────────────────────
CREATE OR REPLACE FUNCTION get_opening_balances(p_club_id uuid)
RETURNS TABLE(
  player_id   uuid,
  player_name text,
  amount      numeric,
  notes       text,
  updated_at  timestamptz
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    ob.player_id,
    COALESCE(up.nickname, p.display_name) AS player_name,
    ob.amount,
    ob.notes,
    ob.updated_at
  FROM paysplit_opening_balances ob
  JOIN players p ON p.id = ob.player_id
  LEFT JOIN user_profiles up ON up.user_id = p.user_id
  WHERE ob.club_id = p_club_id
    AND EXISTS (SELECT 1 FROM club_members cm
                WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
  ORDER BY ABS(ob.amount) DESC;
$$;

GRANT EXECUTE ON FUNCTION set_opening_balance(uuid,uuid,numeric,text) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_opening_balance(uuid,uuid)           TO authenticated;
GRANT EXECUTE ON FUNCTION get_opening_balances(uuid)                  TO authenticated;
