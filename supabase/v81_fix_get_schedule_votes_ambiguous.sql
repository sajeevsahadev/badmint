-- v81_fix_get_schedule_votes_ambiguous
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- get_schedule_votes threw "column reference user_id is ambiguous": the
-- RETURNS TABLE(user_id ...) out-column collided with club_members.user_id in
-- the membership check. The frontend swallows the RPC error, so the votes list
-- silently showed "No votes yet" even though votes exist. Qualify the column.
CREATE OR REPLACE FUNCTION public.get_schedule_votes(p_schedule_id uuid)
RETURNS TABLE(user_id uuid, vote text, voted_at timestamptz, display_name text, is_present boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_club_id uuid; v_max int;
BEGIN
  SELECT cs.club_id, cs.max_attendees INTO v_club_id, v_max
  FROM club_schedule cs WHERE cs.id = p_schedule_id;
  IF v_club_id IS NULL THEN RETURN; END IF;

  -- Members only. Qualify cm.user_id so it can't be read as the OUT column.
  IF NOT EXISTS (
    SELECT 1 FROM club_members cm
    WHERE cm.club_id = v_club_id AND cm.user_id = auth.uid()
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH ranked AS (
    SELECT sv.user_id AS uid, sv.vote AS v, sv.voted_at AS vat,
      CASE WHEN sv.vote = 'attending'
           THEN row_number() OVER (PARTITION BY sv.vote ORDER BY sv.voted_at) END AS att_rank
    FROM schedule_votes sv WHERE sv.schedule_id = p_schedule_id
  )
  SELECT r.uid, r.v, r.vat,
    COALESCE(up.nickname, up.full_name, pl.display_name, au.raw_user_meta_data->>'full_name', 'Member') AS display_name,
    CASE WHEN r.v = 'attending' THEN (COALESCE(v_max,0) = 0 OR r.att_rank <= v_max) ELSE false END AS is_present
  FROM ranked r
  LEFT JOIN user_profiles up ON up.user_id = r.uid
  LEFT JOIN players pl       ON pl.user_id = r.uid AND pl.club_id = v_club_id
  LEFT JOIN auth.users au    ON au.id      = r.uid
  ORDER BY r.vat ASC;
END;
$$;;
