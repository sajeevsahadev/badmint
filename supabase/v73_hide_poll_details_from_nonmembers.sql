-- v73_hide_poll_details_from_nonmembers
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- get_schedule_detail: non-members get basic info (date/club/venue) but NOT counts/votes
DROP FUNCTION IF EXISTS get_schedule_detail(uuid);
CREATE OR REPLACE FUNCTION public.get_schedule_detail(p_schedule_id uuid)
RETURNS TABLE(id uuid, club_id uuid, club_name text, scheduled_date date, facility_id uuid,
  facility_name text, fac_name text, status text, attending_count integer,
  not_attending_count integer, my_vote text, is_member boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    cs.id, cs.club_id, c.name AS club_name, cs.scheduled_date, cs.facility_id,
    cs.facility_name, f.name AS fac_name, cs.status,
    CASE WHEN mem.ok THEN COUNT(sv.id) FILTER (WHERE sv.vote = 'attending')::int END     AS attending_count,
    CASE WHEN mem.ok THEN COUNT(sv.id) FILTER (WHERE sv.vote = 'not_attending')::int END AS not_attending_count,
    CASE WHEN mem.ok THEN MAX(sv.vote) FILTER (WHERE sv.user_id = auth.uid()) END         AS my_vote,
    mem.ok AS is_member
  FROM club_schedule cs
  JOIN clubs c ON c.id = cs.club_id
  LEFT JOIN facilities f ON f.id = cs.facility_id
  LEFT JOIN schedule_votes sv ON sv.schedule_id = cs.id
  CROSS JOIN LATERAL (
    SELECT EXISTS (SELECT 1 FROM club_members cm
                   WHERE cm.club_id = cs.club_id AND cm.user_id = auth.uid()) AS ok
  ) mem
  WHERE cs.id = p_schedule_id
  GROUP BY cs.id, cs.club_id, c.name, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name, cs.status, mem.ok;
END;
$function$;
GRANT EXECUTE ON FUNCTION get_schedule_detail(uuid) TO anon, authenticated;

-- get_schedule_votes: members only (non-members get nothing)
CREATE OR REPLACE FUNCTION public.get_schedule_votes(p_schedule_id uuid)
RETURNS TABLE(user_id uuid, vote text, voted_at timestamptz, display_name text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_club_id uuid;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF v_club_id IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = v_club_id AND user_id = auth.uid()) THEN
    RETURN;   -- non-members see no voter details
  END IF;

  RETURN QUERY
  SELECT sv.user_id, sv.vote, sv.voted_at,
    COALESCE(up.nickname, up.full_name, pl.display_name, au.raw_user_meta_data->>'full_name', 'Member') AS display_name
  FROM schedule_votes sv
  LEFT JOIN user_profiles up ON up.user_id = sv.user_id
  LEFT JOIN players pl       ON pl.user_id = sv.user_id AND pl.club_id = v_club_id
  LEFT JOIN auth.users au    ON au.id      = sv.user_id
  WHERE sv.schedule_id = p_schedule_id
  ORDER BY sv.voted_at ASC;
END;
$function$;;
