-- =====================================================================
-- Badmint v20 — Open poll voting + public leaderboard RPC
-- Run once in Supabase SQL Editor (safe re-run; uses CREATE OR REPLACE)
-- =====================================================================

-- ── vote_schedule: allow any authenticated user to vote ──
-- Removed club-membership requirement so the WhatsApp poll link works
-- for everyone with a Google account, not just club members.
CREATE OR REPLACE FUNCTION vote_schedule(
  p_schedule_id uuid,
  p_vote        text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in to vote';
  END IF;
  IF p_vote NOT IN ('attending', 'not_attending') THEN
    RAISE EXCEPTION 'Vote must be attending or not_attending';
  END IF;

  INSERT INTO schedule_votes(schedule_id, user_id, vote, voted_at)
  VALUES (p_schedule_id, auth.uid(), p_vote, now())
  ON CONFLICT (schedule_id, user_id) DO UPDATE
    SET vote = EXCLUDED.vote, voted_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION vote_schedule(uuid, text) TO authenticated;


-- ── get_schedule_votes: no membership guard, accessible to anon ──
-- Removed club-membership check so the public poll page can show
-- voter names without requiring the viewer to be a club member.
CREATE OR REPLACE FUNCTION get_schedule_votes(p_schedule_id uuid)
RETURNS TABLE (
  user_id      uuid,
  vote         text,
  voted_at     timestamptz,
  display_name text
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club_id uuid;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;

  RETURN QUERY
  SELECT
    sv.user_id,
    sv.vote,
    sv.voted_at,
    COALESCE(up.nickname, up.full_name, pl.display_name, 'Member') AS display_name
  FROM schedule_votes sv
  LEFT JOIN user_profiles up ON up.user_id = sv.user_id
  LEFT JOIN players pl ON pl.user_id = sv.user_id AND pl.club_id = v_club_id
  WHERE sv.schedule_id = p_schedule_id
  ORDER BY sv.voted_at ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_schedule_votes(uuid) TO authenticated, anon;


-- ── get_club_leaderboard: public leaderboard for any club ──
-- SECURITY DEFINER bypasses the v_leaderboard / players RLS so that
-- non-members can view a club's public profile leaderboard.
CREATE OR REPLACE FUNCTION get_club_leaderboard(p_club_id uuid)
RETURNS TABLE (
  id           uuid,
  display_name text,
  elo          int,
  games        bigint,
  wins         bigint,
  win_pct      numeric,
  days_played  bigint,
  club_rank    bigint
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    vl.id,
    vl.display_name,
    vl.elo,
    vl.games,
    vl.wins,
    vl.win_pct,
    vl.days_played,
    vl.club_rank
  FROM v_leaderboard vl
  WHERE vl.club_id = p_club_id
  ORDER BY vl.club_rank;
END;
$$;
GRANT EXECUTE ON FUNCTION get_club_leaderboard(uuid) TO authenticated, anon;
