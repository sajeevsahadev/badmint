-- v74_poll_fully_member_gated
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

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
    cs.id,
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
    mem.ok
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
GRANT EXECUTE ON FUNCTION get_schedule_detail(uuid) TO anon, authenticated;;
