-- v110_tournaments_drawtype_and_admin_create
-- Expose draw_type in the tournament list (so the card shows the real format),
-- and restrict tournament creation to app admins.

DROP FUNCTION IF EXISTS public.get_tournaments(uuid, text, text);
CREATE OR REPLACE FUNCTION public.get_tournaments(
  p_club_id uuid DEFAULT NULL, p_status text DEFAULT NULL, p_emirate text DEFAULT NULL)
RETURNS TABLE(id uuid, club_id uuid, club_name text, name text, description text,
  format text, draw_type text, status text, max_teams integer, entry_fee numeric,
  prize_info text, venue text, emirate text, registration_end date, start_date date,
  end_date date, confirmed_teams bigint, pending_teams bigint, winner_team_name text,
  created_by uuid, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT t.id, t.club_id, c.name AS club_name,
    t.name, t.description, t.format, t.draw_type, t.status,
    t.max_teams, t.entry_fee, t.prize_info, t.venue, t.emirate,
    t.registration_end, t.start_date, t.end_date,
    (SELECT COUNT(*) FROM tournament_registrations r WHERE r.tournament_id=t.id AND r.status='confirmed') AS confirmed_teams,
    (SELECT COUNT(*) FROM tournament_registrations r WHERE r.tournament_id=t.id AND r.status='pending')   AS pending_teams,
    (SELECT tr.team_name FROM tournament_registrations tr WHERE tr.id=t.winner_registration_id)           AS winner_team_name,
    t.created_by, t.created_at
  FROM tournaments t
  JOIN clubs c ON c.id = t.club_id
  WHERE (p_club_id IS NULL OR t.club_id = p_club_id)
    AND (p_status  IS NULL OR t.status  = p_status)
    AND (p_emirate IS NULL OR t.emirate = p_emirate)
  ORDER BY CASE t.status WHEN 'live' THEN 1 WHEN 'registration_open' THEN 2 WHEN 'completed' THEN 3 ELSE 4 END,
    t.start_date DESC NULLS LAST, t.created_at DESC;
END;$$;
GRANT EXECUTE ON FUNCTION public.get_tournaments(uuid,text,text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_tournament(
  p_club_id uuid, p_name text, p_draw_type text DEFAULT 'knockout', p_max_teams integer DEFAULT 16,
  p_description text DEFAULT NULL, p_entry_fee numeric DEFAULT NULL, p_prize_info text DEFAULT NULL,
  p_venue text DEFAULT NULL, p_venue_address text DEFAULT NULL, p_emirate text DEFAULT NULL,
  p_registration_end date DEFAULT NULL, p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL,
  p_courts integer DEFAULT 1, p_is_public boolean DEFAULT true, p_maps_url text DEFAULT NULL,
  p_groups_count integer DEFAULT 0, p_advance_per_group integer DEFAULT 2)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid; v_format text;
BEGIN
  IF NOT is_app_admin() THEN
    RAISE EXCEPTION 'Only app admins can create tournaments';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM clubs WHERE id = p_club_id) THEN
    RAISE EXCEPTION 'Club not found';
  END IF;
  IF p_draw_type NOT IN ('knockout','round_robin','groups_knockout') THEN RAISE EXCEPTION 'Invalid draw type'; END IF;
  v_format := CASE WHEN p_draw_type='round_robin' THEN 'round_robin' ELSE 'single_elimination' END;
  INSERT INTO tournaments (club_id,name,format,draw_type,max_teams,description,entry_fee,prize_info,
    venue,venue_address,emirate,maps_url,registration_end,start_date,end_date,courts,is_public,
    groups_count,advance_per_group,created_by)
  VALUES (p_club_id,p_name,v_format,p_draw_type,p_max_teams,p_description,p_entry_fee,p_prize_info,
    p_venue,p_venue_address,p_emirate,p_maps_url,p_registration_end,p_start_date,p_end_date,
    GREATEST(1,COALESCE(p_courts,1)),COALESCE(p_is_public,true),COALESCE(p_groups_count,0),
    COALESCE(p_advance_per_group,2),auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;$$;
