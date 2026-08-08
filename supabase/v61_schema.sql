-- =====================================================================
-- Badminton 360 v61 — chat sender names fall back to the Google account
-- Run in Supabase SQL Editor (after v60_schema.sql).
--
-- get_club_messages / get_message_sender resolved names from user_profiles
-- only (COALESCE(nickname, full_name, 'Player')). Members who never set up a
-- profile showed as the literal "Player". These are SECURITY DEFINER, so they
-- can read auth.users — fall back to the Google display name / avatar, then the
-- email local-part, before the generic 'Player'. (Mirrors get_schedule_votes.)
-- =====================================================================

CREATE OR REPLACE FUNCTION get_club_messages(p_club_id uuid, p_before timestamptz DEFAULT NULL, p_limit int DEFAULT 40)
RETURNS TABLE(
  id uuid, user_id uuid, body text, created_at timestamptz,
  sender_name text, avatar_url text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM (
    SELECT m.id, m.user_id, m.body, m.created_at,
           COALESCE(
             NULLIF(up.nickname, ''),
             NULLIF(up.full_name, ''),
             NULLIF(au.raw_user_meta_data->>'full_name', ''),
             NULLIF(au.raw_user_meta_data->>'name', ''),
             NULLIF(split_part(au.email, '@', 1), ''),
             'Player'
           ) AS sender_name,
           COALESCE(up.avatar_url, au.raw_user_meta_data->>'avatar_url', au.raw_user_meta_data->>'picture') AS avatar_url
    FROM club_messages m
    LEFT JOIN user_profiles up ON up.user_id = m.user_id
    LEFT JOIN auth.users     au ON au.id      = m.user_id
    WHERE m.club_id = p_club_id
      AND (EXISTS (SELECT 1 FROM club_members cm
                   WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
           OR is_app_admin())
      AND (p_before IS NULL OR m.created_at < p_before)
    ORDER BY m.created_at DESC
    LIMIT GREATEST(1, LEAST(p_limit, 100))
  ) page
  ORDER BY created_at ASC;
$$;

CREATE OR REPLACE FUNCTION get_message_sender(p_club_id uuid, p_user_id uuid)
RETURNS TABLE(sender_name text, avatar_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(
           NULLIF(up.nickname, ''),
           NULLIF(up.full_name, ''),
           NULLIF(au.raw_user_meta_data->>'full_name', ''),
           NULLIF(au.raw_user_meta_data->>'name', ''),
           NULLIF(split_part(au.email, '@', 1), ''),
           'Player'
         ),
         COALESCE(up.avatar_url, au.raw_user_meta_data->>'avatar_url', au.raw_user_meta_data->>'picture')
  FROM auth.users au
  LEFT JOIN user_profiles up ON up.user_id = au.id
  WHERE au.id = p_user_id
    AND (EXISTS (SELECT 1 FROM club_members cm
                 WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
         OR is_app_admin());
$$;

REVOKE EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_message_sender(uuid, uuid)            FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int) TO authenticated;
GRANT  EXECUTE ON FUNCTION get_message_sender(uuid, uuid)            TO authenticated;
