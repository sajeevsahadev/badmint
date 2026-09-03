-- v101_tournament_phase1_rpcs
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Auto share_code for every new tournament.
CREATE OR REPLACE FUNCTION public.set_tournament_share_code() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.share_code IS NULL THEN
    NEW.share_code := lower(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  END IF;
  RETURN NEW;
END;$$;
DROP TRIGGER IF EXISTS trg_tournament_share_code ON tournaments;
CREATE TRIGGER trg_tournament_share_code BEFORE INSERT ON tournaments
  FOR EACH ROW EXECUTE FUNCTION public.set_tournament_share_code();

-- Who may manage a tournament: its creator, the club's owner/manager, or a director.
CREATE OR REPLACE FUNCTION public._can_manage_tournament(p_tournament_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (
    SELECT 1 FROM tournaments t
    WHERE t.id = p_tournament_id AND (
      t.created_by = auth.uid()
      OR EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = t.club_id AND cm.user_id = auth.uid() AND cm.role IN ('owner','manager'))
      OR is_tournament_director()
    )
  );
$$;

-- create_tournament v2 (draw_type, courts, is_public, maps_url, groups)
DROP FUNCTION IF EXISTS public.create_tournament(uuid,text,text,integer,text,numeric,text,text,text,text,date,date,date);
CREATE OR REPLACE FUNCTION public.create_tournament(
  p_club_id uuid, p_name text,
  p_draw_type text DEFAULT 'knockout', p_max_teams integer DEFAULT 16,
  p_description text DEFAULT NULL, p_entry_fee numeric DEFAULT NULL,
  p_prize_info text DEFAULT NULL, p_venue text DEFAULT NULL,
  p_venue_address text DEFAULT NULL, p_emirate text DEFAULT NULL,
  p_registration_end date DEFAULT NULL, p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL,
  p_courts integer DEFAULT 1, p_is_public boolean DEFAULT true, p_maps_url text DEFAULT NULL,
  p_groups_count integer DEFAULT 0, p_advance_per_group integer DEFAULT 2
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id uuid; v_format text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id=p_club_id AND user_id=auth.uid() AND role IN ('owner','manager'))
  THEN RAISE EXCEPTION 'Only club managers or owners can create tournaments'; END IF;
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

-- update_tournament_details v2
DROP FUNCTION IF EXISTS public.update_tournament_details(uuid,text,text,numeric,text,text,text,text,date,date,date,integer);
CREATE OR REPLACE FUNCTION public.update_tournament_details(
  p_tournament_id uuid, p_name text DEFAULT NULL, p_description text DEFAULT NULL,
  p_entry_fee numeric DEFAULT NULL, p_prize_info text DEFAULT NULL, p_venue text DEFAULT NULL,
  p_venue_address text DEFAULT NULL, p_emirate text DEFAULT NULL, p_registration_end date DEFAULT NULL,
  p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_max_teams integer DEFAULT NULL,
  p_draw_type text DEFAULT NULL, p_courts integer DEFAULT NULL, p_is_public boolean DEFAULT NULL,
  p_maps_url text DEFAULT NULL, p_groups_count integer DEFAULT NULL, p_advance_per_group integer DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE tournaments SET
    name=COALESCE(p_name,name), description=COALESCE(p_description,description),
    entry_fee=COALESCE(p_entry_fee,entry_fee), prize_info=COALESCE(p_prize_info,prize_info),
    venue=COALESCE(p_venue,venue), venue_address=COALESCE(p_venue_address,venue_address),
    emirate=COALESCE(p_emirate,emirate), registration_end=COALESCE(p_registration_end,registration_end),
    start_date=COALESCE(p_start_date,start_date), end_date=COALESCE(p_end_date,end_date),
    max_teams=COALESCE(p_max_teams,max_teams), draw_type=COALESCE(p_draw_type,draw_type),
    courts=COALESCE(p_courts,courts), is_public=COALESCE(p_is_public,is_public),
    maps_url=COALESCE(p_maps_url,maps_url), groups_count=COALESCE(p_groups_count,groups_count),
    advance_per_group=COALESCE(p_advance_per_group,advance_per_group), updated_at=now()
  WHERE id=p_tournament_id;
END;$$;

-- register_for_tournament v2 (contact, links the registrant, payment pending, one team per user)
DROP FUNCTION IF EXISTS public.register_for_tournament(uuid,text,text,text,text);
CREATE OR REPLACE FUNCTION public.register_for_tournament(
  p_tournament_id uuid, p_team_name text, p_player_a_name text,
  p_player_b_name text DEFAULT NULL, p_notes text DEFAULT NULL, p_contact_phone text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_tour record; v_count int; v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required to register'; END IF;
  SELECT * INTO v_tour FROM tournaments WHERE id=p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF v_tour.status <> 'registration_open' THEN RAISE EXCEPTION 'Registration is not open for this tournament'; END IF;
  SELECT COUNT(*) INTO v_count FROM tournament_registrations WHERE tournament_id=p_tournament_id AND status IN ('pending','confirmed');
  IF v_count >= v_tour.max_teams THEN RAISE EXCEPTION 'Tournament is full (% teams)', v_tour.max_teams; END IF;
  IF EXISTS (SELECT 1 FROM tournament_registrations WHERE tournament_id=p_tournament_id AND registered_by=auth.uid() AND status <> 'rejected')
  THEN RAISE EXCEPTION 'You have already registered a team for this tournament'; END IF;
  INSERT INTO tournament_registrations (tournament_id,team_name,player_a_name,player_b_name,registered_by,notes,contact_phone,player_a_user_id,status,payment_status)
  VALUES (p_tournament_id,trim(p_team_name),trim(p_player_a_name),NULLIF(trim(p_player_b_name),''),auth.uid(),p_notes,p_contact_phone,auth.uid(),'pending','pending')
  RETURNING id INTO v_id;
  RETURN v_id;
END;$$;

-- Approve / reject / mark paid (managers). status: pending|confirmed|rejected.
CREATE OR REPLACE FUNCTION public.set_registration_status(p_reg_id uuid, p_status text, p_paid boolean DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_tid uuid;
BEGIN
  SELECT tournament_id INTO v_tid FROM tournament_registrations WHERE id=p_reg_id;
  IF v_tid IS NULL THEN RAISE EXCEPTION 'Registration not found'; END IF;
  IF NOT _can_manage_tournament(v_tid) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_status NOT IN ('pending','confirmed','rejected') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  UPDATE tournament_registrations SET
    status = p_status,
    payment_status = CASE WHEN p_paid IS NULL THEN payment_status WHEN p_paid THEN 'confirmed' ELSE 'pending' END
  WHERE id=p_reg_id;
END;$$;

-- Public tournament (anyone with the link/code — no login). Powers public + register pages.
CREATE OR REPLACE FUNCTION public.get_public_tournament(p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb; v_tid uuid;
BEGIN
  SELECT id INTO v_tid FROM tournaments WHERE share_code = p_code OR id::text = p_code LIMIT 1;
  IF v_tid IS NULL THEN RETURN NULL; END IF;
  SELECT jsonb_build_object(
    'tournament', jsonb_build_object(
      'id',t.id,'name',t.name,'club_id',t.club_id,'club_name',c.name,'description',t.description,
      'draw_type',t.draw_type,'status',t.status,'max_teams',t.max_teams,'entry_fee',t.entry_fee,
      'prize_info',t.prize_info,'venue',t.venue,'venue_address',t.venue_address,'maps_url',t.maps_url,
      'emirate',t.emirate,'registration_end',t.registration_end,'start_date',t.start_date,'end_date',t.end_date,
      'is_public',t.is_public,'share_code',t.share_code,'courts',t.courts,
      'winner_registration_id',t.winner_registration_id,'runner_up_registration_id',t.runner_up_registration_id,
      'third_registration_id',t.third_registration_id,'cover_photo_url',t.cover_photo_url,'group_photo_url',t.group_photo_url),
    'teams', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'team_name',tr.team_name,'player_a_name',tr.player_a_name,'player_b_name',tr.player_b_name,'seed',tr.seed) ORDER BY COALESCE(tr.seed,9999), tr.created_at)
             FROM tournament_registrations tr WHERE tr.tournament_id=v_tid AND tr.status='confirmed'),'[]'),
    'confirmed_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='confirmed'),
    'pending_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='pending')
  ) INTO v FROM tournaments t JOIN clubs c ON c.id=t.club_id WHERE t.id=v_tid;
  RETURN v;
END;$$;

-- Public list (for sitemap + discovery) — only is_public tournaments.
CREATE OR REPLACE FUNCTION public.get_public_tournaments()
RETURNS TABLE(id uuid, share_code text, name text, club_name text, status text, start_date date, updated_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT t.id, t.share_code, t.name, c.name, t.status, t.start_date, t.updated_at
  FROM tournaments t JOIN clubs c ON c.id=t.club_id
  WHERE t.is_public = true ORDER BY t.start_date DESC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_tournament(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_tournaments() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_registration_status(uuid,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public._can_manage_tournament(uuid) TO authenticated;;
