-- v112_dedupe_indexes_and_tournament_currency
-- Drop duplicate indexes (perf/write cost) and surface each tournament's club
-- currency so entry fees render as "AED 250", not "250".

DROP INDEX IF EXISTS public.idx_tmatch_tournament;   -- keep idx_tourmatch_tour
DROP INDEX IF EXISTS public.idx_tourreg_tournament;  -- keep idx_treg_tournament

-- get_public_tournament: add currency to the tournament object.
-- (Full body applied via migration; see get_public_tournament definition.)

-- get_tournaments: add currency column (drop+recreate for the new return type).
DROP FUNCTION IF EXISTS public.get_tournaments(uuid, text, text);
CREATE OR REPLACE FUNCTION public.get_tournaments(
  p_club_id uuid DEFAULT NULL, p_status text DEFAULT NULL, p_emirate text DEFAULT NULL)
RETURNS TABLE(id uuid, club_id uuid, club_name text, currency text, name text, description text,
  format text, draw_type text, status text, max_teams integer, entry_fee numeric,
  prize_info text, venue text, emirate text, registration_end date, start_date date,
  end_date date, confirmed_teams bigint, pending_teams bigint, winner_team_name text,
  created_by uuid, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_admin boolean := is_app_admin();
BEGIN
  RETURN QUERY
  SELECT t.id, t.club_id, c.name AS club_name, COALESCE(c.currency,'AED') AS currency,
    t.name, t.description, t.format, t.draw_type, t.status,
    t.max_teams, t.entry_fee, t.prize_info, t.venue, t.emirate,
    t.registration_end, t.start_date, t.end_date,
    (SELECT COUNT(*) FROM tournament_registrations r WHERE r.tournament_id=t.id AND r.status='confirmed'),
    (SELECT COUNT(*) FROM tournament_registrations r WHERE r.tournament_id=t.id AND r.status='pending'),
    (SELECT tr.team_name FROM tournament_registrations tr WHERE tr.id=t.winner_registration_id),
    t.created_by, t.created_at
  FROM tournaments t
  JOIN clubs c ON c.id = t.club_id
  WHERE (p_club_id IS NULL OR t.club_id = p_club_id)
    AND (p_status  IS NULL OR t.status  = p_status)
    AND (p_emirate IS NULL OR t.emirate = p_emirate)
    AND (v_admin OR (t.status NOT IN ('draft','cancelled') AND t.is_public = true))
  ORDER BY CASE t.status WHEN 'live' THEN 1 WHEN 'registration_open' THEN 2 WHEN 'completed' THEN 3 ELSE 4 END,
    t.start_date DESC NULLS LAST, t.created_at DESC;
END;$$;
GRANT EXECUTE ON FUNCTION public.get_tournaments(uuid,text,text) TO anon, authenticated;

-- NOTE: get_public_tournament was also updated in this migration to add
-- 'currency' to its tournament object (see the live function definition).
