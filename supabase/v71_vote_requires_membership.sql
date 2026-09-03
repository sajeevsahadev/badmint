-- v71_vote_requires_membership
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

CREATE OR REPLACE FUNCTION public.vote_schedule(p_schedule_id uuid, p_vote text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_club_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in to vote';
  END IF;
  IF p_vote NOT IN ('attending', 'not_attending') THEN
    RAISE EXCEPTION 'Vote must be attending or not_attending';
  END IF;

  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF v_club_id IS NULL THEN
    RAISE EXCEPTION 'Schedule not found';
  END IF;

  -- Only members of THIS club may respond to its poll.
  IF NOT EXISTS (
    SELECT 1 FROM club_members WHERE club_id = v_club_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only club members can respond to this poll. Join the club first.';
  END IF;

  INSERT INTO schedule_votes(schedule_id, user_id, vote, voted_at)
  VALUES (p_schedule_id, auth.uid(), p_vote, now())
  ON CONFLICT (schedule_id, user_id) DO UPDATE
    SET vote = EXCLUDED.vote, voted_at = now();
END;
$function$;;
