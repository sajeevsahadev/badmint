-- v89_club_matches_dedupe_players
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Avatars are stored as (large) base64 data URIs. Returning them per-participant
-- repeats each player's avatar across every match → huge payload. Return a
-- deduped players map instead; matches carry only player ids + elo.
CREATE OR REPLACE FUNCTION public.get_club_matches(
  p_club_id uuid, p_limit integer DEFAULT 30, p_before timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH page AS (
    SELECT m.id, m.played_on, m.created_at, m.created_by, m.display_name, m.match_number
    FROM matches m
    WHERE m.club_id = p_club_id
      AND (p_before IS NULL OR m.created_at < p_before)
      AND EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
    ORDER BY m.created_at DESC
    LIMIT greatest(p_limit, 1)
  )
  SELECT jsonb_build_object(
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pg.id, 'played_on', pg.played_on, 'created_at', pg.created_at,
        'created_by', pg.created_by, 'display_name', pg.display_name, 'match_number', pg.match_number,
        'sides', (
          SELECT jsonb_agg(jsonb_build_object(
            'side', ms.side, 'score', ms.score, 'is_winner', ms.is_winner,
            'players', (
              SELECT jsonb_agg(jsonb_build_object(
                'id', mp.player_id, 'elo_before', mp.elo_before, 'elo_after', mp.elo_after) ORDER BY mp.id)
              FROM match_participants mp WHERE mp.match_side_id = ms.id)
          ) ORDER BY ms.side)
          FROM match_sides ms WHERE ms.match_id = pg.id)
      ) ORDER BY pg.created_at DESC)
      FROM page pg), '[]'::jsonb),
    'players', COALESCE((
      SELECT jsonb_object_agg(pl.id, jsonb_build_object(
        'name', COALESCE(up.nickname, pl.display_name), 'user_id', pl.user_id, 'avatar', up.avatar_url))
      FROM players pl LEFT JOIN user_profiles up ON up.user_id = pl.user_id
      WHERE pl.id IN (
        SELECT mp.player_id FROM match_participants mp
        JOIN match_sides ms ON ms.id = mp.match_side_id
        WHERE ms.match_id IN (SELECT id FROM page))), '{}'::jsonb)
  );
$$;
GRANT EXECUTE ON FUNCTION public.get_club_matches(uuid, integer, timestamptz) TO authenticated;;
