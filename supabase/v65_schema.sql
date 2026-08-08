-- =====================================================================
-- Badminton 360 v65 — "Message info" (read receipts) for chat
-- Run after v64_schema.sql.
--
-- Only the message author (or an app admin) may view it — like WhatsApp.
-- Per club member (excluding the author):
--   read      → their club_chat_reads.last_read_at is at/after the message
--   delivered → not read, but they have a push subscription (we pushed them)
--   sent      → not read and no subscription
-- "Delivered" is a best-effort proxy: a PWA has no true per-device receipt.
-- =====================================================================

CREATE OR REPLACE FUNCTION get_message_info(p_message_id uuid)
RETURNS TABLE(user_id uuid, name text, avatar_url text, read_at timestamptz, status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club uuid; v_author uuid; v_created timestamptz;
BEGIN
  SELECT club_id, user_id, created_at INTO v_club, v_author, v_created
  FROM club_messages WHERE id = p_message_id;
  IF v_club IS NULL THEN RAISE EXCEPTION 'Message not found'; END IF;
  -- IS DISTINCT FROM so a NULL auth.uid() can never pass the author check
  IF v_author IS DISTINCT FROM auth.uid() AND NOT is_app_admin() THEN
    RAISE EXCEPTION 'Only the sender can view message info';
  END IF;

  RETURN QUERY
    SELECT cm.user_id,
           chat_display_name(cm.user_id) AS name,
           COALESCE(up.avatar_url, au.raw_user_meta_data->>'avatar_url', au.raw_user_meta_data->>'picture') AS avatar_url,
           CASE WHEN r.last_read_at >= v_created THEN r.last_read_at END AS read_at,
           CASE WHEN r.last_read_at >= v_created THEN 'read'
                WHEN EXISTS (SELECT 1 FROM push_subscriptions ps WHERE ps.user_id = cm.user_id) THEN 'delivered'
                ELSE 'sent' END AS status
    FROM club_members cm
    LEFT JOIN club_chat_reads r ON r.club_id = v_club AND r.user_id = cm.user_id
    LEFT JOIN user_profiles   up ON up.user_id = cm.user_id
    LEFT JOIN auth.users      au ON au.id      = cm.user_id
    WHERE cm.club_id = v_club AND cm.user_id <> v_author
    ORDER BY (CASE WHEN r.last_read_at >= v_created THEN 0 ELSE 1 END),
             r.last_read_at DESC NULLS LAST,
             chat_display_name(cm.user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION get_message_info(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION get_message_info(uuid) TO authenticated;
