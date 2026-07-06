-- =====================================================================
-- Badminton 360 v55 — Weekly digest: "This Week's Champions" summary
-- Run in Supabase SQL Editor. (Already applied to prod.)
--
-- The digest email gained a second section. It now shows:
--   1. "This Week's Champions" — only players who actually played in the
--      last 7 days, with their W/L and Elo change this week (MVP first).
--   2. "Overall Standings" — the all-time top 5 (unchanged).
-- This RPC powers section 1.
-- =====================================================================

-- Per-player performance over the last N days (default 7): games, wins,
-- losses, and Elo change. Ranked champions-first (most wins, then Elo gain).
-- Only active players who actually played in the window appear.
CREATE OR REPLACE FUNCTION get_club_weekly_summary(p_club_id uuid, p_days int DEFAULT 7)
RETURNS TABLE(
  player_id uuid, user_id uuid, display_name text,
  games int, wins int, losses int, elo_delta int
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH mp AS (
    SELECT mp.player_id, mp.elo_before, mp.elo_after, ms.is_winner,
           m.played_on, m.created_at, mp.id AS mp_id
    FROM match_participants mp
    JOIN match_sides ms ON ms.id = mp.match_side_id
    JOIN matches m ON m.id = ms.match_id
    WHERE m.club_id = p_club_id
      AND m.played_on >= (current_date - p_days)
  ),
  agg AS (
    SELECT player_id,
      count(*)::int                                 AS games,
      count(*) FILTER (WHERE is_winner)::int        AS wins,
      count(*) FILTER (WHERE NOT is_winner)::int    AS losses,
      (array_agg(elo_before ORDER BY played_on ASC,  created_at ASC,  mp_id ASC))[1]  AS first_before,
      (array_agg(elo_after  ORDER BY played_on DESC, created_at DESC, mp_id DESC))[1] AS last_after
    FROM mp GROUP BY player_id
  )
  SELECT a.player_id, p.user_id,
         COALESCE(resolve_public_nickname(p.user_id), p.display_name) AS display_name,
         a.games, a.wins, a.losses,
         round(a.last_after - a.first_before)::int AS elo_delta
  FROM agg a
  JOIN players p ON p.id = a.player_id
  WHERE p.is_active = true
  ORDER BY a.wins DESC, (a.last_after - a.first_before) DESC, a.games DESC;
$$;

GRANT EXECUTE ON FUNCTION get_club_weekly_summary(uuid, int) TO authenticated, anon;

-- The send-weekly-digest Edge Function also gained a test_email mode
-- (sends exactly one preview email to a given address) — deployed
-- separately, no SQL change.
