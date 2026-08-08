-- =====================================================================
-- Badminton 360 v58 — Club Chat (text + emoji, one room per club)
-- Run in Supabase SQL Editor.
--
-- A simple WhatsApp-style room scoped to each club: members post text
-- (emojis are just text), messages are stored and read newest-first with
-- pagination, live-updated via Supabase Realtime, and a push notification
-- fires to other members (client calls the notify-chat Edge Function).
-- =====================================================================

CREATE TABLE IF NOT EXISTS club_messages (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id    uuid NOT NULL REFERENCES clubs(id)      ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_messages_body_len CHECK (char_length(body) BETWEEN 1 AND 2000)
);

CREATE INDEX IF NOT EXISTS idx_club_messages_club_created
  ON club_messages(club_id, created_at DESC);

ALTER TABLE club_messages ENABLE ROW LEVEL SECURITY;

-- Members can read their club's messages (also gates Realtime delivery).
DROP POLICY IF EXISTS cm_read ON club_messages;
CREATE POLICY cm_read ON club_messages FOR SELECT
  USING (EXISTS (SELECT 1 FROM club_members m
                 WHERE m.club_id = club_messages.club_id AND m.user_id = auth.uid()));

-- Members can post as themselves.
DROP POLICY IF EXISTS cm_insert ON club_messages;
CREATE POLICY cm_insert ON club_messages FOR INSERT
  WITH CHECK (user_id = auth.uid()
             AND EXISTS (SELECT 1 FROM club_members m
                         WHERE m.club_id = club_messages.club_id AND m.user_id = auth.uid()));

-- A user can delete their own message; owners/managers can moderate any.
DROP POLICY IF EXISTS cm_delete ON club_messages;
CREATE POLICY cm_delete ON club_messages FOR DELETE
  USING (user_id = auth.uid()
         OR EXISTS (SELECT 1 FROM club_members m
                    WHERE m.club_id = club_messages.club_id AND m.user_id = auth.uid()
                      AND m.role IN ('owner','manager')));

-- Live updates
ALTER PUBLICATION supabase_realtime ADD TABLE club_messages;

-- ── post_club_message: insert + return the row (trims, membership-checked) ──
CREATE OR REPLACE FUNCTION post_club_message(p_club_id uuid, p_body text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id uuid; v_body text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  v_body := btrim(p_body);
  IF v_body = '' THEN RAISE EXCEPTION 'Message is empty'; END IF;
  IF char_length(v_body) > 2000 THEN v_body := left(v_body, 2000); END IF;

  INSERT INTO club_messages(club_id, user_id, body)
  VALUES (p_club_id, auth.uid(), v_body)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION post_club_message(uuid, text) TO authenticated;

-- ── get_club_messages: page of messages with sender name + avatar ──
-- Returns oldest→newest within the page; p_before pages backwards in time.
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
      AND EXISTS (SELECT 1 FROM club_members cm
                  WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
      AND (p_before IS NULL OR m.created_at < p_before)
    ORDER BY m.created_at DESC
    LIMIT GREATEST(1, LEAST(p_limit, 100))
  ) page
  ORDER BY created_at ASC;
$$;
GRANT EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int) TO authenticated;

-- Sender-name resolver for a single message (used to label Realtime inserts
-- that arrive with only raw columns). Members-only, one user at a time.
CREATE OR REPLACE FUNCTION get_message_sender(p_club_id uuid, p_user_id uuid)
RETURNS TABLE(sender_name text, avatar_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(up.nickname, up.full_name, 'Player'), up.avatar_url
  FROM user_profiles up
  WHERE up.user_id = p_user_id
    AND EXISTS (SELECT 1 FROM club_members cm
                WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid());
$$;
GRANT EXECUTE ON FUNCTION get_message_sender(uuid, uuid) TO authenticated;

-- Security: keep these off the anon role (they self-protect via the
-- membership check, but no logged-out caller should reach chat at all).
REVOKE EXECUTE ON FUNCTION post_club_message(uuid, text)             FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_club_messages(uuid, timestamptz, int) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_message_sender(uuid, uuid)            FROM PUBLIC, anon;
