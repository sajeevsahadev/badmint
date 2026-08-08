-- =====================================================================
-- Badminton 360 v59 — Super-admin oversight of all club chats
-- Run in Supabase SQL Editor (after v58_schema.sql).
--
-- App admins can read (not post to) any club's chat for moderation/safety.
-- Extends the read policy + read RPCs with `OR is_app_admin()`. Posting
-- and deletion remain member/owner-scoped (admins moderate via the DB if
-- ever needed; the admin UI is read-only).
-- =====================================================================

-- ── Read policy: members OR app admin ───────────────────────────────
DROP POLICY IF EXISTS cm_read ON club_messages;
CREATE POLICY cm_read ON club_messages FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM club_members m
            WHERE m.club_id = club_messages.club_id AND m.user_id = auth.uid())
    OR is_app_admin()
  );

-- ── get_club_messages: allow admin to read any club ─────────────────
CREATE OR REPLACE FUNCTION get_club_messages(p_club_id uuid, p_before timestamptz DEFAULT NULL, p_limit int DEFAULT 40)
RETURNS TABLE(
  id uuid, user_id uuid, body text, created_at timestamptz,
  sender_name text, avatar_url text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM (
    SELECT m.id, m.user_id, m.body, m.created_at,
           COALESCE(up.nickname, up.full_name, 'Player') AS sender_name,
           up.avatar_url
    FROM club_messages m
    LEFT JOIN user_profiles up ON up.user_id = m.user_id
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
  SELECT COALESCE(up.nickname, up.full_name, 'Player'), up.avatar_url
  FROM user_profiles up
  WHERE up.user_id = p_user_id
    AND (EXISTS (SELECT 1 FROM club_members cm
                 WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
         OR is_app_admin());
$$;

REVOKE EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_message_sender(uuid, uuid)            FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int) TO authenticated;
GRANT  EXECUTE ON FUNCTION get_message_sender(uuid, uuid)            TO authenticated;
