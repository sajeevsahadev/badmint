-- =====================================================================
-- Badminton 360 v64 — unread chat tracking
-- Run after v63_schema.sql.
--
-- Per-user "last read" marker per club; an unread count = messages posted by
-- others since then. Used to badge the Club Chat entry points.
-- =====================================================================

CREATE TABLE IF NOT EXISTS club_chat_reads (
  club_id      uuid NOT NULL REFERENCES clubs(id)      ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (club_id, user_id)
);
ALTER TABLE club_chat_reads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ccr_own ON club_chat_reads;
CREATE POLICY ccr_own ON club_chat_reads FOR ALL
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Mark the current user's chat for a club as read (now).
CREATE OR REPLACE FUNCTION mark_chat_read(p_club_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO club_chat_reads (club_id, user_id, last_read_at)
  VALUES (p_club_id, auth.uid(), now())
  ON CONFLICT (club_id, user_id) DO UPDATE SET last_read_at = now();
$$;

-- Count messages from OTHERS since the user last read this club's chat.
CREATE OR REPLACE FUNCTION get_chat_unread_count(p_club_id uuid)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN NOT EXISTS (
           SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()
         ) THEN 0
         ELSE (
           SELECT count(*)::int FROM club_messages m
           WHERE m.club_id = p_club_id
             AND m.deleted_at IS NULL
             AND m.user_id <> auth.uid()
             AND m.created_at > COALESCE(
               (SELECT last_read_at FROM club_chat_reads
                WHERE club_id = p_club_id AND user_id = auth.uid()),
               'epoch'::timestamptz)
         ) END;
$$;

REVOKE EXECUTE ON FUNCTION mark_chat_read(uuid)        FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_chat_unread_count(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION mark_chat_read(uuid)        TO authenticated;
GRANT  EXECUTE ON FUNCTION get_chat_unread_count(uuid) TO authenticated;
