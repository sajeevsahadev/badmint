-- v88_perf_top_scorers_and_matches
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Perf: fast top-scorers, one-shot paginated club matches, sort index.

-- Sort index for the matches history (ordered by created_at within a club).
CREATE INDEX IF NOT EXISTS idx_matches_club_created ON matches (club_id, created_at DESC);

-- ── Fast top scorers ──
-- Old version scanned the whole v_leaderboard and called resolve_public_nickname
-- per row (a query each). This aggregates match_participants once, resolves the
-- nickname with a direct join (SECURITY DEFINER bypasses RLS), and limits.
CREATE OR REPLACE FUNCTION public.get_top_scorers(p_limit integer DEFAULT 50)
RETURNS TABLE(player_id uuid, user_id uuid, public_name text, club_name text,
              emirates text, elo integer, games integer, win_pct numeric, global_rank bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH agg AS (
    SELECT mp.player_id,
           count(*)::int AS games,
           count(*) FILTER (WHERE ms.is_winner)::int AS wins
    FROM match_participants mp
    JOIN match_sides ms ON ms.id = mp.match_side_id
    GROUP BY mp.player_id
  )
  SELECT p.id, p.user_id,
         COALESCE(up.nickname, p.display_name) AS public_name,
         c.name, c.emirates,
         round(p.elo)::int AS elo,
         a.games,
         round(100.0 * a.wins / NULLIF(a.games, 0), 1) AS win_pct,
         rank() OVER (ORDER BY p.elo DESC) AS global_rank
  FROM players p
  JOIN clubs c ON c.id = p.club_id
  JOIN agg a   ON a.player_id = p.id
  LEFT JOIN user_profiles up ON up.user_id = p.user_id
  WHERE p.is_active AND a.games >= 1
  ORDER BY p.elo DESC
  LIMIT p_limit;
$$;
GRANT EXECUTE ON FUNCTION public.get_top_scorers(integer) TO anon, authenticated;

-- ── One-shot, paginated club match history (nicknames + avatars inline) ──
-- Replaces the PostgREST embed + a second buildProfileMap round trip. Keyset
-- pagination on created_at (pass the oldest loaded created_at as p_before).
-- Members-only (match detail is club-internal).
CREATE OR REPLACE FUNCTION public.get_club_matches(
  p_club_id uuid, p_limit integer DEFAULT 30, p_before timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_agg(sub.row ORDER BY sub.ord DESC), '[]'::jsonb)
  FROM (
    SELECT m.created_at AS ord,
      jsonb_build_object(
        'id', m.id, 'played_on', m.played_on, 'created_at', m.created_at,
        'created_by', m.created_by, 'display_name', m.display_name, 'match_number', m.match_number,
        'sides', (
          SELECT jsonb_agg(jsonb_build_object(
            'side', ms.side, 'score', ms.score, 'is_winner', ms.is_winner,
            'players', (
              SELECT jsonb_agg(jsonb_build_object(
                'id', pl.id, 'name', COALESCE(up.nickname, pl.display_name),
                'user_id', pl.user_id, 'avatar', up.avatar_url,
                'elo_before', mp.elo_before, 'elo_after', mp.elo_after) ORDER BY pl.display_name)
              FROM match_participants mp
              JOIN players pl ON pl.id = mp.player_id
              LEFT JOIN user_profiles up ON up.user_id = pl.user_id
              WHERE mp.match_side_id = ms.id)
          ) ORDER BY ms.side)
          FROM match_sides ms WHERE ms.match_id = m.id)
      ) AS row
    FROM matches m
    WHERE m.club_id = p_club_id
      AND (p_before IS NULL OR m.created_at < p_before)
      AND EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
    ORDER BY m.created_at DESC
    LIMIT greatest(p_limit, 1)
  ) sub;
$$;
GRANT EXECUTE ON FUNCTION public.get_club_matches(uuid, integer, timestamptz) TO authenticated;;
