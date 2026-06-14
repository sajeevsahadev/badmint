-- =====================================================================
-- Badmint v27 — Performance indexes for scale
-- Run once in Supabase SQL Editor
-- All statements use IF NOT EXISTS — safe to re-run
-- =====================================================================

-- ── CRITICAL: is_member() / is_manager() called on every authenticated request ──
-- Without this, every RLS policy evaluation scans all of club_members by user_id
CREATE INDEX IF NOT EXISTS idx_club_members_user_id
  ON club_members(user_id);

-- ── CRITICAL: v_leaderboard and delete_match Elo replay ──
-- match_sides.match_id has no index — hit on every leaderboard aggregation
CREATE INDEX IF NOT EXISTS idx_match_sides_match_id
  ON match_sides(match_id);

-- match_participants.match_side_id — hit on every participant lookup in replay loop
CREATE INDEX IF NOT EXISTS idx_match_participants_side_id
  ON match_participants(match_side_id);

-- ── HIGH: player lookups ──
-- players.user_id — used in get_club_players, v_leaderboard join, leave_club, online status
CREATE INDEX IF NOT EXISTS idx_players_user_id
  ON players(user_id);

-- Composite for the most common filter: active players in a club
CREATE INDEX IF NOT EXISTS idx_players_club_active
  ON players(club_id, is_active);

-- ── HIGH: PaySplits — 1M expense entries need these ──
CREATE INDEX IF NOT EXISTS idx_paysplit_expenses_club
  ON paysplit_expenses(club_id, expense_date DESC);

CREATE INDEX IF NOT EXISTS idx_paysplit_expenses_paid_player
  ON paysplit_expenses(paid_player_id)
  WHERE paid_player_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_paysplit_expenses_created_by
  ON paysplit_expenses(created_by);

CREATE INDEX IF NOT EXISTS idx_paysplit_participants_player
  ON paysplit_participants(player_id);

CREATE INDEX IF NOT EXISTS idx_paysplit_notes_club
  ON paysplit_notes(club_id);

CREATE INDEX IF NOT EXISTS idx_wallet_contributions_club
  ON wallet_contributions(club_id, contributed_at);

CREATE INDEX IF NOT EXISTS idx_wallet_contributions_player
  ON wallet_contributions(player_id);

-- ── MEDIUM: facility lookups ──
CREATE INDEX IF NOT EXISTS idx_facilities_emirate
  ON facilities(emirate);

CREATE INDEX IF NOT EXISTS idx_facilities_created_by
  ON facilities(created_by);

CREATE INDEX IF NOT EXISTS idx_facility_schedule_facility
  ON facility_schedule(facility_id);

CREATE INDEX IF NOT EXISTS idx_facility_bookings_facility_date
  ON facility_bookings(facility_id, booked_date);

CREATE INDEX IF NOT EXISTS idx_facility_bookings_club
  ON facility_bookings(club_id);

CREATE INDEX IF NOT EXISTS idx_clubs_facility_id
  ON clubs(facility_id)
  WHERE facility_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_clubs_created_by
  ON clubs(created_by);

-- ── MEDIUM: join / invite tables ──
CREATE INDEX IF NOT EXISTS idx_join_requests_user_status
  ON join_requests(user_id, status);

CREATE INDEX IF NOT EXISTS idx_club_invites_club_id
  ON club_invites(club_id);

CREATE INDEX IF NOT EXISTS idx_club_invites_guest_player
  ON club_invites(guest_player_id)
  WHERE guest_player_id IS NOT NULL;

-- ── MEDIUM: tournament bracket navigation ──
CREATE INDEX IF NOT EXISTS idx_tourmatch_next_match
  ON tournament_matches(next_match_id)
  WHERE next_match_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tourmatch_round_pos
  ON tournament_matches(tournament_id, round, position);

CREATE INDEX IF NOT EXISTS idx_tournaments_created_by
  ON tournaments(created_by);

-- ── MEDIUM: schedule attendees ──
CREATE INDEX IF NOT EXISTS idx_schedule_attendees_player
  ON schedule_attendees(player_id);

-- ── LOW: match auth + activity log ──
CREATE INDEX IF NOT EXISTS idx_matches_created_by
  ON matches(created_by);

CREATE INDEX IF NOT EXISTS idx_activity_event_type
  ON activity_log(event_type, created_at DESC);

-- =====================================================================
-- NOTES FOR FUTURE MIGRATIONS (require schema changes, not just indexes)
-- =====================================================================

-- 1. v_leaderboard FULL TABLE SCAN RISK
--    The view's sub-queries aggregate ALL match_participants and attendance
--    rows without a club_id filter. At 1M matches this will be slow.
--    Fix: rewrite the sub-queries to filter by club_id before aggregating,
--    or MATERIALIZE the view and refresh after each record_match call.
--
-- 2. delete_match TIMEOUT RISK
--    The Elo replay loop iterates row-by-row in PL/pgSQL.
--    Clubs with 300+ matches will hit Supabase's 10s PostgREST timeout.
--    Fix: rewrite replay to set-based CTEs, or move to a background job.
--
-- 3. v_club_rankings and v_top_scorers
--    Should be materialized and refreshed every 10-15 minutes.
--    Run: CREATE MATERIALIZED VIEW mv_club_rankings AS SELECT * FROM v_club_rankings;
--    Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY mv_club_rankings;
--    Add a pg_cron job or trigger after record_match.
