-- v76_schedule_slot_rpcs
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

DROP FUNCTION IF EXISTS get_club_schedule(uuid, integer, integer);
CREATE OR REPLACE FUNCTION public.get_club_schedule(p_club_id uuid, p_year integer, p_month integer)
RETURNS TABLE(id uuid, scheduled_date date, facility_id uuid, facility_name text, fac_name text,
  status text, attending_count integer, not_attending_count integer, my_vote text,
  start_time time, end_time time, max_attendees integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member';
  END IF;
  RETURN QUERY
  SELECT cs.id, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name AS fac_name, cs.status,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'attending')::int,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'not_attending')::int,
    MAX(sv.vote) FILTER (WHERE sv.user_id = auth.uid()),
    cs.start_time, cs.end_time, cs.max_attendees
  FROM club_schedule cs
  LEFT JOIN facilities f ON f.id = cs.facility_id
  LEFT JOIN schedule_votes sv ON sv.schedule_id = cs.id
  WHERE cs.club_id = p_club_id
    AND EXTRACT(YEAR FROM cs.scheduled_date) = p_year
    AND EXTRACT(MONTH FROM cs.scheduled_date) = p_month
  GROUP BY cs.id, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name, cs.status,
           cs.start_time, cs.end_time, cs.max_attendees
  ORDER BY cs.scheduled_date, cs.start_time NULLS FIRST;
END;
$function$;
GRANT EXECUTE ON FUNCTION get_club_schedule(uuid, integer, integer) TO authenticated;

DROP FUNCTION IF EXISTS get_schedule_detail(uuid);
CREATE OR REPLACE FUNCTION public.get_schedule_detail(p_schedule_id uuid)
RETURNS TABLE(id uuid, club_id uuid, club_name text, scheduled_date date, facility_id uuid,
  facility_name text, fac_name text, status text, attending_count integer,
  not_attending_count integer, my_vote text, is_member boolean,
  start_time time, end_time time, max_attendees integer, my_position integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT cs.id,
    CASE WHEN mem.ok THEN cs.club_id END,
    CASE WHEN mem.ok THEN c.name END,
    CASE WHEN mem.ok THEN cs.scheduled_date END,
    CASE WHEN mem.ok THEN cs.facility_id END,
    CASE WHEN mem.ok THEN cs.facility_name END,
    CASE WHEN mem.ok THEN f.name END,
    CASE WHEN mem.ok THEN cs.status END,
    CASE WHEN mem.ok THEN COUNT(sv.id) FILTER (WHERE sv.vote = 'attending')::int END,
    CASE WHEN mem.ok THEN COUNT(sv.id) FILTER (WHERE sv.vote = 'not_attending')::int END,
    CASE WHEN mem.ok THEN MAX(sv.vote) FILTER (WHERE sv.user_id = auth.uid()) END,
    mem.ok,
    CASE WHEN mem.ok THEN cs.start_time END,
    CASE WHEN mem.ok THEN cs.end_time END,
    CASE WHEN mem.ok THEN cs.max_attendees END,
    CASE WHEN mem.ok THEN (
      SELECT q.rn FROM (
        SELECT sv2.user_id, row_number() OVER (ORDER BY sv2.voted_at)::int AS rn
        FROM schedule_votes sv2 WHERE sv2.schedule_id = cs.id AND sv2.vote = 'attending'
      ) q WHERE q.user_id = auth.uid()
    ) END
  FROM club_schedule cs
  JOIN clubs c ON c.id = cs.club_id
  LEFT JOIN facilities f ON f.id = cs.facility_id
  LEFT JOIN schedule_votes sv ON sv.schedule_id = cs.id
  CROSS JOIN LATERAL (
    SELECT EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = cs.club_id AND cm.user_id = auth.uid()) AS ok
  ) mem
  WHERE cs.id = p_schedule_id
  GROUP BY cs.id, cs.club_id, c.name, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name,
           cs.status, mem.ok, cs.start_time, cs.end_time, cs.max_attendees;
END;
$function$;
GRANT EXECUTE ON FUNCTION get_schedule_detail(uuid) TO anon, authenticated;

DROP FUNCTION IF EXISTS get_schedule_votes(uuid);
CREATE OR REPLACE FUNCTION public.get_schedule_votes(p_schedule_id uuid)
RETURNS TABLE(user_id uuid, vote text, voted_at timestamptz, display_name text, is_present boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_club_id uuid; v_max int;
BEGIN
  SELECT club_id, max_attendees INTO v_club_id, v_max FROM club_schedule WHERE id = p_schedule_id;
  IF v_club_id IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = v_club_id AND user_id = auth.uid()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH ranked AS (
    SELECT sv.user_id, sv.vote, sv.voted_at,
      CASE WHEN sv.vote = 'attending'
           THEN row_number() OVER (PARTITION BY sv.vote ORDER BY sv.voted_at) END AS att_rank
    FROM schedule_votes sv WHERE sv.schedule_id = p_schedule_id
  )
  SELECT r.user_id, r.vote, r.voted_at,
    COALESCE(up.nickname, up.full_name, pl.display_name, au.raw_user_meta_data->>'full_name', 'Member') AS display_name,
    CASE WHEN r.vote = 'attending' THEN (COALESCE(v_max,0) = 0 OR r.att_rank <= v_max) ELSE false END AS is_present
  FROM ranked r
  LEFT JOIN user_profiles up ON up.user_id = r.user_id
  LEFT JOIN players pl       ON pl.user_id = r.user_id AND pl.club_id = v_club_id
  LEFT JOIN auth.users au    ON au.id      = r.user_id
  ORDER BY r.voted_at ASC;
END;
$function$;;
