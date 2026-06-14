-- =====================================================================
-- Badmint v29 — admin_delete_club: admin can force-delete any club
-- Run once in Supabase SQL Editor
-- =====================================================================

-- admin_delete_club: app_admin can delete any club regardless of ownership.
-- Skips the match-count guard that delete_club enforces for regular owners.
-- All dependent data removed via ON DELETE CASCADE from clubs:
--   club_members, ranking_config, players, matches → match_sides →
--   match_participants, attendance, join_requests, club_invites,
--   facility_bookings, paysplit_expenses → paysplit_participants,
--   paysplit_notes, paysplit_opening_balances, wallet_contributions,
--   playing_schedule, tournaments
CREATE OR REPLACE FUNCTION admin_delete_club(p_club_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_name text;
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT name INTO v_name FROM clubs WHERE id = p_club_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Club not found'; END IF;
  DELETE FROM clubs WHERE id = p_club_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_delete_club(uuid) TO authenticated;
