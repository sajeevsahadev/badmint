-- =====================================================================
-- Badmint v34 — Admin: full player profile + match history (bypass RLS)
-- Run in Supabase SQL Editor after v33_schema.sql
-- Both functions verify app_admin role before returning any data.
-- =====================================================================

-- ── admin_get_player: player base row + club info ─────────────────────
CREATE OR REPLACE FUNCTION admin_get_player(p_player_id uuid)
RETURNS TABLE(
  id           uuid,
  display_name text,
  elo          numeric,
  club_id      uuid,
  user_id      uuid,
  is_active    boolean,
  club_name    text,
  emirates     text
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM app_roles ar WHERE ar.user_id = auth.uid() AND ar.role = 'app_admin'
  ) THEN RAISE EXCEPTION 'Admin access required'; END IF;

  RETURN QUERY
  SELECT p.id, p.display_name, p.elo, p.club_id, p.user_id, p.is_active,
         c.name AS club_name, c.emirates
  FROM players p
  JOIN clubs c ON c.id = p.club_id
  WHERE p.id = p_player_id;
END;
$$;

-- ── admin_get_player_matches: full match history for any player ────────
CREATE OR REPLACE FUNCTION admin_get_player_matches(
  p_player_id uuid,
  p_limit     int DEFAULT 30
)
RETURNS TABLE(
  match_id     uuid,
  played_on    date,
  match_number int,
  display_name text,
  side_a       jsonb,
  side_b       jsonb
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_club_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM app_roles ar WHERE ar.user_id = auth.uid() AND ar.role = 'app_admin'
  ) THEN RAISE EXCEPTION 'Admin access required'; END IF;

  SELECT p.club_id INTO v_club_id FROM players p WHERE p.id = p_player_id;

  RETURN QUERY
  SELECT
    m.id,
    m.played_on,
    m.match_number,
    m.display_name,
    jsonb_build_object(
      'score', sa.score,
      'is_winner', sa.is_winner,
      'participants', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'player_id',   mp.player_id,
          'display_name', COALESCE(up.nickname, pl.display_name),
          'elo_before',  mp.elo_before,
          'elo_after',   mp.elo_after
        ))
        FROM match_participants mp
        JOIN players pl ON pl.id = mp.player_id
        LEFT JOIN user_profiles up ON up.user_id = pl.user_id
        WHERE mp.match_side_id = sa.id
      ), '[]'::jsonb)
    ) AS side_a,
    jsonb_build_object(
      'score', sb.score,
      'is_winner', sb.is_winner,
      'participants', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'player_id',   mp.player_id,
          'display_name', COALESCE(up.nickname, pl.display_name),
          'elo_before',  mp.elo_before,
          'elo_after',   mp.elo_after
        ))
        FROM match_participants mp
        JOIN players pl ON pl.id = mp.player_id
        LEFT JOIN user_profiles up ON up.user_id = pl.user_id
        WHERE mp.match_side_id = sb.id
      ), '[]'::jsonb)
    ) AS side_b
  FROM matches m
  JOIN match_sides sa ON sa.match_id = m.id AND sa.side = 'A'
  JOIN match_sides sb ON sb.match_id = m.id AND sb.side = 'B'
  WHERE m.club_id = v_club_id
    AND EXISTS (
      SELECT 1 FROM match_sides ms
      JOIN match_participants mp ON mp.match_side_id = ms.id
      WHERE ms.match_id = m.id AND mp.player_id = p_player_id
    )
  ORDER BY m.played_on DESC, m.created_at DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_player(uuid)              TO authenticated;
GRANT EXECUTE ON FUNCTION admin_get_player_matches(uuid, int) TO authenticated;
