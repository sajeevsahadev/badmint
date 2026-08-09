-- =====================================================================
-- Badminton 360 v66 — image messages in club chat (stored on Cloudflare R2)
-- Run after v65_schema.sql.
--
-- Images live in R2 (bucket b360-chat-images, served from
-- images.badminton360.app); club_messages only stores the public URL + the
-- compressed dimensions. Uploads go phone → R2 directly via a presigned URL
-- from the r2-upload-url Edge Function, so image bytes never touch the DB.
-- =====================================================================

ALTER TABLE club_messages ALTER COLUMN body DROP NOT NULL;   -- image-only messages have no text
ALTER TABLE club_messages ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE club_messages ADD COLUMN IF NOT EXISTS image_w   int;
ALTER TABLE club_messages ADD COLUMN IF NOT EXISTS image_h   int;

-- post_club_message: optional image (+ dimensions); body may be blank if image present
DROP FUNCTION IF EXISTS post_club_message(uuid, text, uuid, boolean);
CREATE OR REPLACE FUNCTION post_club_message(
  p_club_id uuid, p_body text, p_reply_to uuid DEFAULT NULL, p_is_forwarded boolean DEFAULT false,
  p_image_url text DEFAULT NULL, p_image_w int DEFAULT NULL, p_image_h int DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_body text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  v_body := NULLIF(btrim(coalesce(p_body, '')), '');
  IF v_body IS NULL AND p_image_url IS NULL THEN
    RAISE EXCEPTION 'Empty message';
  END IF;
  -- only accept our own R2 image host
  IF p_image_url IS NOT NULL AND p_image_url NOT LIKE 'https://images.badminton360.app/%' THEN
    RAISE EXCEPTION 'Invalid image URL';
  END IF;
  IF p_reply_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM club_messages WHERE id = p_reply_to AND club_id = p_club_id
  ) THEN
    p_reply_to := NULL;
  END IF;
  INSERT INTO club_messages (club_id, user_id, body, reply_to, is_forwarded, image_url, image_w, image_h)
  VALUES (p_club_id, auth.uid(), v_body, p_reply_to, p_is_forwarded, p_image_url, p_image_w, p_image_h)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- get_club_messages: now also returns image_url/image_w/image_h
DROP FUNCTION IF EXISTS get_club_messages(uuid, timestamptz, int);
CREATE OR REPLACE FUNCTION get_club_messages(p_club_id uuid, p_before timestamptz DEFAULT NULL, p_limit int DEFAULT 40)
RETURNS TABLE(
  id uuid, user_id uuid, body text, created_at timestamptz,
  sender_name text, avatar_url text,
  reply_to uuid, reply_sender text, reply_body text,
  is_forwarded boolean, deleted boolean, starred boolean,
  image_url text, image_w int, image_h int
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
                  WHEN rm.body IS NOT NULL THEN left(rm.body, 120)
                  WHEN rm.image_url IS NOT NULL THEN '📷 Photo'
                  ELSE '' END
           END AS reply_body,
           m.is_forwarded,
           (m.deleted_at IS NOT NULL) AS deleted,
           (st.user_id IS NOT NULL) AS starred,
           CASE WHEN m.deleted_at IS NOT NULL THEN NULL ELSE m.image_url END AS image_url,
           m.image_w, m.image_h
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

REVOKE EXECUTE ON FUNCTION post_club_message(uuid, text, uuid, boolean, text, int, int) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int)                     FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION post_club_message(uuid, text, uuid, boolean, text, int, int)  TO authenticated;
GRANT  EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int)                     TO authenticated;
