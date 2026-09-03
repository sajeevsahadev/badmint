-- v83_schedule_detail_expose_join_policy
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Expose club_id, club_name, join_policy to NON-members so the poll page can
-- auto-join public clubs. Sensitive poll data (date, venue, counts, my_vote,
-- times, position) stays member-gated exactly as before. club_id/name/policy
-- are already public via get_public_clubs, so this leaks nothing new.
DROP FUNCTION IF EXISTS public.get_schedule_detail(uuid);
CREATE FUNCTION public.get_schedule_detail(p_schedule_id uuid)
RETURNS TABLE(id uuid, club_id uuid, club_name text, scheduled_date date, facility_id uuid,
  facility_name text, fac_name text, status text, attending_count integer, not_attending_count integer,
  my_vote text, is_member boolean, start_time time without time zone, end_time time without time zone,
  max_attendees integer, my_position integer, join_policy text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT cs.id,
    cs.club_id,                                     -- public (needed to auto-join)
    c.name,                                         -- public
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
    ) END,
    c.join_policy                                   -- public (drives auto-join)
  FROM club_schedule cs
  JOIN clubs c ON c.id = cs.club_id
  LEFT JOIN facilities f ON f.id = cs.facility_id
  LEFT JOIN schedule_votes sv ON sv.schedule_id = cs.id
  CROSS JOIN LATERAL (
    SELECT EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = cs.club_id AND cm.user_id = auth.uid()) AS ok
  ) mem
  WHERE cs.id = p_schedule_id
  GROUP BY cs.id, cs.club_id, c.name, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name,
           cs.status, mem.ok, cs.start_time, cs.end_time, cs.max_attendees, c.join_policy;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_schedule_detail(uuid) TO anon, authenticated;;
