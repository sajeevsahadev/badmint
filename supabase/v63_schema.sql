-- =====================================================================
-- Badminton 360 v63 — chat message actions: Reply, Forward, Star, Delete
-- (React already exists in v62). Run after v62_schema.sql.
-- =====================================================================

-- ── New columns on club_messages ────────────────────────────────────────
ALTER TABLE club_messages
  ADD COLUMN IF NOT EXISTS reply_to     uuid REFERENCES club_messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_forwarded boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at   timestamptz;

-- ── Per-user starred (bookmarked) messages ──────────────────────────────
CREATE TABLE IF NOT EXISTS club_message_stars (
  message_id uuid NOT NULL REFERENCES club_messages(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES auth.users(id)    ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);
ALTER TABLE club_message_stars ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cms_own ON club_message_stars;
CREATE POLICY cms_own ON club_message_stars FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ── Sender display-name helper (nickname → full_name → Google → email) ───
CREATE OR REPLACE FUNCTION chat_display_name(p_user_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
           NULLIF(up.nickname, ''), NULLIF(up.full_name, ''),
           NULLIF(au.raw_user_meta_data->>'full_name', ''),
           NULLIF(au.raw_user_meta_data->>'name', ''),
           NULLIF(split_part(au.email, '@', 1), ''), 'Player')
  FROM auth.users au LEFT JOIN user_profiles up ON up.user_id = au.id
  WHERE au.id = p_user_id;
$$;

-- ── post_club_message: now supports reply_to + is_forwarded ─────────────
DROP FUNCTION IF EXISTS post_club_message(uuid, text);
CREATE OR REPLACE FUNCTION post_club_message(
  p_club_id uuid, p_body text, p_reply_to uuid DEFAULT NULL, p_is_forwarded boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  -- reply_to (when given) must be a live message in the same club
  IF p_reply_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM club_messages WHERE id = p_reply_to AND club_id = p_club_id
  ) THEN
    p_reply_to := NULL;
  END IF;
  INSERT INTO club_messages (club_id, user_id, body, reply_to, is_forwarded)
  VALUES (p_club_id, auth.uid(), p_body, p_reply_to, p_is_forwarded)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ── get_club_messages: reply preview, forwarded flag, deleted, starred ──
DROP FUNCTION IF EXISTS get_club_messages(uuid, timestamptz, int);
CREATE OR REPLACE FUNCTION get_club_messages(p_club_id uuid, p_before timestamptz DEFAULT NULL, p_limit int DEFAULT 40)
RETURNS TABLE(
  id uuid, user_id uuid, body text, created_at timestamptz,
  sender_name text, avatar_url text,
  reply_to uuid, reply_sender text, reply_body text,
  is_forwarded boolean, deleted boolean, starred boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM (
    SELECT m.id, m.user_id,
           CASE WHEN m.deleted_at IS NOT NULL THEN NULL ELSE m.body END AS body,
           m.created_at,
           COALESCE(NULLIF(up.nickname,''), NULLIF(up.full_name,''),
                    NULLIF(au.raw_user_meta_data->>'full_name',''),
                    NULLIF(au.raw_user_meta_data->>'name',''),
                    NULLIF(split_part(au.email,'@',1),''), 'Player') AS sender_name,
           COALESCE(up.avatar_url, au.raw_user_meta_data->>'avatar_url', au.raw_user_meta_data->>'picture') AS avatar_url,
           m.reply_to,
           CASE WHEN m.reply_to IS NOT NULL THEN chat_display_name(rm.user_id) END AS reply_sender,
           CASE WHEN m.reply_to IS NOT NULL THEN
             CASE WHEN rm.deleted_at IS NOT NULL THEN 'Deleted message'
                  ELSE left(rm.body, 120) END
           END AS reply_body,
           m.is_forwarded,
           (m.deleted_at IS NOT NULL) AS deleted,
           (st.user_id IS NOT NULL) AS starred
    FROM club_messages m
    LEFT JOIN user_profiles up ON up.user_id = m.user_id
    LEFT JOIN auth.users     au ON au.id      = m.user_id
    LEFT JOIN club_messages  rm ON rm.id      = m.reply_to
    LEFT JOIN club_message_stars st ON st.message_id = m.id AND st.user_id = auth.uid()
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

-- ── Delete (soft): author, or club owner/manager (moderation) ───────────
CREATE OR REPLACE FUNCTION delete_club_message(p_message_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club uuid; v_author uuid;
BEGIN
  SELECT club_id, user_id INTO v_club, v_author FROM club_messages WHERE id = p_message_id;
  IF v_club IS NULL THEN RAISE EXCEPTION 'Message not found'; END IF;
  IF v_author = auth.uid()
     OR EXISTS (SELECT 1 FROM club_members WHERE club_id = v_club AND user_id = auth.uid()
                AND role IN ('owner','manager')) THEN
    UPDATE club_messages SET deleted_at = now() WHERE id = p_message_id;
    DELETE FROM club_message_reactions WHERE message_id = p_message_id;
  ELSE
    RAISE EXCEPTION 'Not allowed to delete this message';
  END IF;
END;
$$;

-- ── Star toggle ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION toggle_message_star(p_message_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club uuid;
BEGIN
  SELECT club_id INTO v_club FROM club_messages WHERE id = p_message_id;
  IF v_club IS NULL THEN RAISE EXCEPTION 'Message not found'; END IF;
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = v_club AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  IF EXISTS (SELECT 1 FROM club_message_stars WHERE message_id = p_message_id AND user_id = auth.uid()) THEN
    DELETE FROM club_message_stars WHERE message_id = p_message_id AND user_id = auth.uid();
    RETURN false;
  ELSE
    INSERT INTO club_message_stars (message_id, user_id) VALUES (p_message_id, auth.uid());
    RETURN true;
  END IF;
END;
$$;

-- ── Grants ──────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION post_club_message(uuid, text, uuid, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int)     FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION delete_club_message(uuid)                     FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION toggle_message_star(uuid)                     FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION chat_display_name(uuid)                       FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION post_club_message(uuid, text, uuid, boolean)  TO authenticated;
GRANT  EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int)     TO authenticated;
GRANT  EXECUTE ON FUNCTION delete_club_message(uuid)                     TO authenticated;
GRANT  EXECUTE ON FUNCTION toggle_message_star(uuid)                     TO authenticated;
GRANT  EXECUTE ON FUNCTION chat_display_name(uuid)                       TO authenticated, service_role;
