-- v121_get_tournaments_own_drafts
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Now that anyone can create, a user must see their OWN drafts (and any
-- tournament they administer), while the public still only sees live/public ones.
CREATE OR REPLACE FUNCTION public.get_tournaments(
  p_club_id uuid DEFAULT NULL, p_status text DEFAULT NULL, p_emirate text DEFAULT NULL)
RETURNS TABLE(id uuid, slug text, club_id uuid, club_name text, currency text, name text, description text,
  format text, draw_type text, status text, max_teams integer, entry_fee numeric,
  prize_info text, venue text, emirate text, registration_end date, start_date date,
  end_date date, confirmed_teams bigint, pending_teams bigint, winner_team_name text,
  category text, skill_level text, best_of_3 boolean, created_by uuid, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_admin boolean := is_app_admin();
BEGIN
  RETURN QUERY
  SELECT t.id, t.slug, t.club_id, c.name AS club_name, COALESCE(t.currency, c.currency, 'AED') AS currency,
    t.name, t.description, t.format, t.draw_type, t.status,
    t.max_teams, t.entry_fee, t.prize_info, t.venue, t.emirate,
    t.registration_end, t.start_date, t.end_date,
    (SELECT COUNT(*) FROM tournament_registrations r WHERE r.tournament_id=t.id AND r.status='confirmed'),
    (SELECT COUNT(*) FROM tournament_registrations r WHERE r.tournament_id=t.id AND r.status='pending'),
    (SELECT tr.team_name FROM tournament_registrations tr WHERE tr.id=t.winner_registration_id),
    t.category, t.skill_level, t.best_of_3, t.created_by, t.created_at
  FROM tournaments t
  JOIN clubs c ON c.id = t.club_id
  WHERE (p_club_id IS NULL OR t.club_id = p_club_id)
    AND (p_status  IS NULL OR t.status  = p_status)
    AND (p_emirate IS NULL OR t.emirate = p_emirate)
    AND (v_admin
         OR t.created_by = auth.uid()
         OR EXISTS (SELECT 1 FROM tournament_admins ta WHERE ta.tournament_id=t.id AND ta.user_id=auth.uid())
         OR (t.status NOT IN ('draft','cancelled') AND t.is_public = true))
  ORDER BY CASE t.status WHEN 'live' THEN 1 WHEN 'registration_open' THEN 2 WHEN 'completed' THEN 3 ELSE 4 END,
    t.start_date DESC NULLS LAST, t.created_at DESC;
END;$$;
GRANT EXECUTE ON FUNCTION public.get_tournaments(uuid,text,text) TO anon, authenticated;;
