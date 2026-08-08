-- =====================================================================
-- Badminton 360 v62 — emoji reactions on club chat messages
-- Run in Supabase SQL Editor (after v61_schema.sql).
--
-- WhatsApp-style: one reaction per user per message (toggle off by tapping
-- the same emoji, swap by picking a different one). club_id is denormalised
-- onto the row so Realtime can filter by club and RLS is cheap.
-- =====================================================================

CREATE TABLE IF NOT EXISTS club_message_reactions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES club_messages(id) ON DELETE CASCADE,
  club_id    uuid NOT NULL REFERENCES clubs(id)         ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES auth.users(id)    ON DELETE CASCADE,
  emoji      text NOT NULL CHECK (char_length(emoji) BETWEEN 1 AND 32),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id)          -- one reaction per user per message
);

CREATE INDEX IF NOT EXISTS idx_reactions_message ON club_message_reactions(message_id);

-- DELETE events must carry club_id so Realtime's club_id filter matches them.
ALTER TABLE club_message_reactions REPLICA IDENTITY FULL;

ALTER TABLE club_message_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cmr_read ON club_message_reactions;
CREATE POLICY cmr_read ON club_message_reactions FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM club_members m
            WHERE m.club_id = club_message_reactions.club_id AND m.user_id = auth.uid())
    OR is_app_admin()
  );

DROP POLICY IF EXISTS cmr_write ON club_message_reactions;
CREATE POLICY cmr_write ON club_message_reactions FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM club_members m
                WHERE m.club_id = club_message_reactions.club_id AND m.user_id = auth.uid())
  );

-- Live updates
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'club_message_reactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE club_message_reactions;
  END IF;
END $$;

-- ── Toggle a reaction (add / swap / remove) ─────────────────────────────
CREATE OR REPLACE FUNCTION toggle_message_reaction(p_message_id uuid, p_emoji text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_club_id  uuid;
  v_existing text;
BEGIN
  SELECT club_id INTO v_club_id FROM club_messages WHERE id = p_message_id;
  IF v_club_id IS NULL THEN RAISE EXCEPTION 'Message not found'; END IF;

  IF NOT EXISTS (SELECT 1 FROM club_members
                 WHERE club_id = v_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;

  SELECT emoji INTO v_existing
  FROM club_message_reactions
  WHERE message_id = p_message_id AND user_id = auth.uid();

  IF v_existing IS NULL THEN
    INSERT INTO club_message_reactions (message_id, club_id, user_id, emoji)
    VALUES (p_message_id, v_club_id, auth.uid(), p_emoji);
    RETURN p_emoji;
  ELSIF v_existing = p_emoji THEN
    DELETE FROM club_message_reactions
    WHERE message_id = p_message_id AND user_id = auth.uid();
    RETURN NULL;             -- toggled off
  ELSE
    UPDATE club_message_reactions SET emoji = p_emoji, created_at = now()
    WHERE message_id = p_message_id AND user_id = auth.uid();
    RETURN p_emoji;          -- swapped
  END IF;
END;
$$;

-- ── Aggregated reactions for a batch of messages ────────────────────────
CREATE OR REPLACE FUNCTION get_message_reactions(p_message_ids uuid[])
RETURNS TABLE(message_id uuid, emoji text, cnt int, reacted boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT r.message_id, r.emoji, count(*)::int AS cnt,
         bool_or(r.user_id = auth.uid()) AS reacted
  FROM club_message_reactions r
  WHERE r.message_id = ANY(p_message_ids)
    AND (EXISTS (SELECT 1 FROM club_members m
                 WHERE m.club_id = r.club_id AND m.user_id = auth.uid())
         OR is_app_admin())
  GROUP BY r.message_id, r.emoji
  ORDER BY cnt DESC, min(r.created_at);
$$;

REVOKE EXECUTE ON FUNCTION toggle_message_reaction(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_message_reactions(uuid[])       FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION toggle_message_reaction(uuid, text) TO authenticated;
GRANT  EXECUTE ON FUNCTION get_message_reactions(uuid[])       TO authenticated;
