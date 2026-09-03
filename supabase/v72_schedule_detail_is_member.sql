-- v72_schedule_detail_is_member
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
    cs.id, cs.club_id, c.name AS club_name, cs.scheduled_date, cs.facility_id,
    cs.facility_name, f.name AS fac_name, cs.status,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'attending')::int     AS attending_count,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'not_attending')::int AS not_attending_count,
    MAX(sv.vote) FILTER (WHERE sv.user_id = auth.uid())        AS my_vote,
    EXISTS (SELECT 1 FROM club_members cm
            WHERE cm.club_id = cs.club_id AND cm.user_id = auth.uid()) AS is_member
  FROM club_schedule cs
  JOIN clubs c ON c.id = cs.club_id
  LEFT JOIN facilities f ON f.id = cs.facility_id
  LEFT JOIN schedule_votes sv ON sv.schedule_id = cs.id
  WHERE cs.id = p_schedule_id
  GROUP BY cs.id, cs.club_id, c.name, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name, cs.status;
END;
$function$;
GRANT EXECUTE ON FUNCTION get_schedule_detail(uuid) TO anon, authenticated;;
