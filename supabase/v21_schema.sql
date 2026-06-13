-- =====================================================================
-- Badmint v21 — get_schedule_votes: use Google auth name as fallback
-- Run once in Supabase SQL Editor (safe re-run; uses CREATE OR REPLACE)
-- =====================================================================

-- Pull the voter's display name from 4 sources in priority order:
--   1. user_profiles.nickname  (user-set in Profile page)
--   2. user_profiles.full_name (user-set in Profile page)
--   3. players.display_name   (roster name if user is linked to a player)
--   4. auth.users raw_user_meta_data->>'full_name'  (Google OAuth name — always available)
--   5. 'Member' fallback
-- The SECURITY DEFINER context allows reading auth.users as postgres (superuser).

CREATE OR REPLACE FUNCTION get_schedule_votes(p_schedule_id uuid)
RETURNS TABLE (
  user_id      uuid,
  vote         text,
  voted_at     timestamptz,
  display_name text
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club_id uuid;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;

  RETURN QUERY
  SELECT
    sv.user_id,
    sv.vote,
    sv.voted_at,
    COALESCE(
      up.nickname,
      up.full_name,
      pl.display_name,
      au.raw_user_meta_data->>'full_name',
      'Member'
    ) AS display_name
  FROM schedule_votes sv
  LEFT JOIN user_profiles up  ON up.user_id  = sv.user_id
  LEFT JOIN players pl        ON pl.user_id  = sv.user_id AND pl.club_id = v_club_id
  LEFT JOIN auth.users au     ON au.id       = sv.user_id
  WHERE sv.schedule_id = p_schedule_id
  ORDER BY sv.voted_at ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_schedule_votes(uuid) TO authenticated, anon;
