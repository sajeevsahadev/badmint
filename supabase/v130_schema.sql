-- =====================================================================
-- Badminton 360 v130 — Admin "Super User mode" (full club monitoring)
-- Applied to prod via Supabase MCP; archived here for rebuild parity.
--
-- Lets an app_admin, when they switch on Super User mode in the UI, see EVERY
-- club in the club switcher and open each club's full activity screens
-- (leaderboard, matches, players, schedule, PaySplits, chat) for misuse
-- monitoring. Most read RPCs are already SECURITY DEFINER with no membership
-- gate, so they work for any club by id. This migration covers the two gaps:
--   1. admin_list_all_clubs() — feeds every club into the switcher (admin only).
--   2. A read-only is_app_admin() bypass on the tables whose SELECT RLS is
--      is_member()-gated and that some screens read directly (not via a DEFINER
--      RPC): players, matches, match_sides, match_participants, attendance,
--      club_schedule, schedule_votes.
-- WRITE policies are untouched (still is_manager-gated), so monitoring an
-- outside club stays effectively read-only even though the UI renders fully.
-- =====================================================================

-- 1. All clubs for the admin switcher
CREATE OR REPLACE FUNCTION admin_list_all_clubs()
RETURNS TABLE(club_id uuid, name text, logo_url text, currency text, member_count bigint, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  SELECT c.id, c.name, c.logo_url, c.currency,
         (SELECT count(*) FROM club_members cm WHERE cm.club_id = c.id)::bigint,
         c.created_at
  FROM clubs c
  WHERE c.deleted_at IS NULL
  ORDER BY c.name;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_list_all_clubs() TO authenticated;

-- 2. Read-only admin bypass on is_member-gated SELECT policies
ALTER POLICY pl_read ON players
  USING (is_member(club_id) OR is_app_admin());

ALTER POLICY mt_read ON matches
  USING (is_member(club_id) OR is_app_admin());

ALTER POLICY at_read ON attendance
  USING (is_member(club_id) OR is_app_admin());

ALTER POLICY ms_read ON match_sides
  USING ((EXISTS (SELECT 1 FROM matches m WHERE m.id = match_sides.match_id AND is_member(m.club_id))) OR is_app_admin());

ALTER POLICY mp_read ON match_participants
  USING ((EXISTS (SELECT 1 FROM match_sides s JOIN matches m ON m.id = s.match_id
                  WHERE s.id = match_participants.match_side_id AND is_member(m.club_id))) OR is_app_admin());

ALTER POLICY cs_member_select ON club_schedule
  USING ((EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = club_schedule.club_id AND cm.user_id = auth.uid())) OR is_app_admin());

ALTER POLICY sv_member_select ON schedule_votes
  USING ((EXISTS (SELECT 1 FROM club_schedule cs JOIN club_members cm ON cm.club_id = cs.club_id
                  WHERE cs.id = schedule_votes.schedule_id AND cm.user_id = auth.uid())) OR is_app_admin());
