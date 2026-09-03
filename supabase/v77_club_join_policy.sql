-- v77_club_join_policy
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- v77: Club join policy (closed | open | public) + public auto-join
-- closed = no self-join at all (manual invites only)
-- open   = request + manager approval (DEFAULT — existing behaviour)
-- public = anyone with the link auto-joins after login, no approval

ALTER TABLE clubs
  ADD COLUMN IF NOT EXISTS join_policy text NOT NULL DEFAULT 'open';

-- Add the CHECK separately so re-running is safe
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'clubs_join_policy_chk'
  ) THEN
    ALTER TABLE clubs
      ADD CONSTRAINT clubs_join_policy_chk
      CHECK (join_policy IN ('closed','open','public'));
  END IF;
END $$;

-- ── Owner/manager sets the club's join policy ──
CREATE OR REPLACE FUNCTION public.set_club_join_policy(p_club_id uuid, p_policy text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF p_policy NOT IN ('closed','open','public') THEN
    RAISE EXCEPTION 'Invalid join policy';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid()
      AND role IN ('owner','manager')
  ) THEN
    RAISE EXCEPTION 'Only owners or managers can change join settings';
  END IF;
  UPDATE clubs SET join_policy = p_policy WHERE id = p_club_id;
END;
$$;

-- ── Public auto-join (no approval). Only works when join_policy = 'public'. ──
CREATE OR REPLACE FUNCTION public.join_club_public(p_club_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_policy text;
  v_total  integer;
  v_name   text;
  v_email  text;
BEGIN
  SELECT join_policy INTO v_policy FROM clubs WHERE id = p_club_id;
  IF v_policy IS NULL THEN RAISE EXCEPTION 'Club not found'; END IF;

  -- Already a member → idempotent no-op
  IF EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RETURN p_club_id;
  END IF;

  IF v_policy <> 'public' THEN
    RAISE EXCEPTION 'This club is not open to public join. Ask a manager for an invite.';
  END IF;

  -- 5-club limit (memberships + pending requests)
  SELECT (SELECT count(*) FROM club_members  WHERE user_id = auth.uid())
       + (SELECT count(*) FROM join_requests WHERE user_id = auth.uid() AND status = 'pending')
    INTO v_total;
  IF v_total >= 5 THEN
    RAISE EXCEPTION 'You have reached the maximum of 5 clubs. Leave a club before joining another.';
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = auth.uid();
  SELECT COALESCE(nickname, full_name) INTO v_name FROM user_profiles WHERE user_id = auth.uid();

  INSERT INTO club_members(club_id, user_id, role)
    VALUES (p_club_id, auth.uid(), 'player')
    ON CONFLICT DO NOTHING;

  IF NOT EXISTS (SELECT 1 FROM players WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    INSERT INTO players(club_id, user_id, display_name)
      VALUES (p_club_id, auth.uid(),
              COALESCE(NULLIF(trim(v_name), ''), split_part(v_email, '@', 1), 'Player'));
  END IF;

  -- Clear any stale pending/rejected request now that they're in
  DELETE FROM join_requests WHERE club_id = p_club_id AND user_id = auth.uid();

  RETURN p_club_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_club_join_policy(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_club_public(uuid) TO authenticated;;
