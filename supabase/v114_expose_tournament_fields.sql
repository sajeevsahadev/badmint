-- v114_expose_tournament_fields
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- ═══════════════════════════════════════════════════════════════════════
-- v114: thread the new tournament fields (best_of_3, category, skill_level,
-- per-tournament currency) and per-game scores through create/update/read RPCs.
-- ═══════════════════════════════════════════════════════════════════════

-- create_tournament: accept the new fields.
CREATE OR REPLACE FUNCTION public.create_tournament(
  p_club_id uuid, p_name text, p_draw_type text DEFAULT 'knockout', p_max_teams integer DEFAULT 16,
  p_description text DEFAULT NULL, p_entry_fee numeric DEFAULT NULL, p_prize_info text DEFAULT NULL,
  p_venue text DEFAULT NULL, p_venue_address text DEFAULT NULL, p_emirate text DEFAULT NULL,
  p_registration_end date DEFAULT NULL, p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL,
  p_courts integer DEFAULT 1, p_is_public boolean DEFAULT true, p_maps_url text DEFAULT NULL,
  p_groups_count integer DEFAULT 0, p_advance_per_group integer DEFAULT 2,
  p_best_of_3 boolean DEFAULT false, p_category text DEFAULT NULL, p_skill_level text DEFAULT NULL,
  p_currency text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid; v_format text;
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Only app admins can create tournaments'; END IF;
  IF NOT EXISTS (SELECT 1 FROM clubs WHERE id = p_club_id) THEN RAISE EXCEPTION 'Club not found'; END IF;
  IF p_draw_type NOT IN ('knockout','round_robin','groups_knockout') THEN RAISE EXCEPTION 'Invalid draw type'; END IF;
  v_format := CASE WHEN p_draw_type='round_robin' THEN 'round_robin' ELSE 'single_elimination' END;
  INSERT INTO tournaments (club_id,name,format,draw_type,max_teams,description,entry_fee,prize_info,
    venue,venue_address,emirate,maps_url,registration_end,start_date,end_date,courts,is_public,
    groups_count,advance_per_group,best_of_3,category,skill_level,currency,created_by)
  VALUES (p_club_id,p_name,v_format,p_draw_type,p_max_teams,p_description,p_entry_fee,p_prize_info,
    p_venue,p_venue_address,p_emirate,p_maps_url,p_registration_end,p_start_date,p_end_date,
    GREATEST(1,COALESCE(p_courts,1)),COALESCE(p_is_public,true),COALESCE(p_groups_count,0),
    COALESCE(p_advance_per_group,2),COALESCE(p_best_of_3,false),
    NULLIF(trim(p_category),''),NULLIF(trim(p_skill_level),''),NULLIF(trim(p_currency),''),auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;$$;

-- update_tournament_details: accept the new fields.
CREATE OR REPLACE FUNCTION public.update_tournament_details(
  p_tournament_id uuid, p_name text DEFAULT NULL, p_description text DEFAULT NULL,
  p_entry_fee numeric DEFAULT NULL, p_prize_info text DEFAULT NULL, p_venue text DEFAULT NULL,
  p_venue_address text DEFAULT NULL, p_emirate text DEFAULT NULL, p_registration_end date DEFAULT NULL,
  p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_max_teams integer DEFAULT NULL,
  p_draw_type text DEFAULT NULL, p_courts integer DEFAULT NULL, p_is_public boolean DEFAULT NULL,
  p_maps_url text DEFAULT NULL, p_groups_count integer DEFAULT NULL, p_advance_per_group integer DEFAULT NULL,
  p_best_of_3 boolean DEFAULT NULL, p_category text DEFAULT NULL, p_skill_level text DEFAULT NULL,
  p_currency text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
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
    advance_per_group=COALESCE(p_advance_per_group,advance_per_group),
    best_of_3=COALESCE(p_best_of_3,best_of_3),
    category=COALESCE(NULLIF(trim(p_category),''),category),
    skill_level=COALESCE(NULLIF(trim(p_skill_level),''),skill_level),
    currency=COALESCE(NULLIF(trim(p_currency),''),currency),
    updated_at=now()
  WHERE id=p_tournament_id;
END;$$;

-- get_tournaments: add best_of_3, category, skill_level; currency = tournament's or club's.
DROP FUNCTION IF EXISTS public.get_tournaments(uuid, text, text);
CREATE OR REPLACE FUNCTION public.get_tournaments(
  p_club_id uuid DEFAULT NULL, p_status text DEFAULT NULL, p_emirate text DEFAULT NULL)
RETURNS TABLE(id uuid, club_id uuid, club_name text, currency text, name text, description text,
  format text, draw_type text, status text, max_teams integer, entry_fee numeric,
  prize_info text, venue text, emirate text, registration_end date, start_date date,
  end_date date, confirmed_teams bigint, pending_teams bigint, winner_team_name text,
  category text, skill_level text, best_of_3 boolean, created_by uuid, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_admin boolean := is_app_admin();
BEGIN
  RETURN QUERY
  SELECT t.id, t.club_id, c.name AS club_name, COALESCE(t.currency, c.currency, 'AED') AS currency,
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
    AND (v_admin OR (t.status NOT IN ('draft','cancelled') AND t.is_public = true))
  ORDER BY CASE t.status WHEN 'live' THEN 1 WHEN 'registration_open' THEN 2 WHEN 'completed' THEN 3 ELSE 4 END,
    t.start_date DESC NULLS LAST, t.created_at DESC;
END;$$;
GRANT EXECUTE ON FUNCTION public.get_tournaments(uuid,text,text) TO anon, authenticated;

-- get_public_tournament: add best_of_3/category/skill_level + waitlist count; currency = tournament's or club's; matches carry games.
CREATE OR REPLACE FUNCTION public.get_public_tournament(p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v jsonb; v_tid uuid;
BEGIN
  SELECT id INTO v_tid FROM tournaments WHERE share_code = p_code OR id::text = p_code LIMIT 1;
  IF v_tid IS NULL THEN RETURN NULL; END IF;
  SELECT jsonb_build_object(
    'tournament', jsonb_build_object(
      'id',t.id,'name',t.name,'club_id',t.club_id,'club_name',c.name,
      'currency',COALESCE(t.currency,c.currency,'AED'),'description',t.description,
      'draw_type',t.draw_type,'status',t.status,'max_teams',t.max_teams,'entry_fee',t.entry_fee,
      'best_of_3',t.best_of_3,'category',t.category,'skill_level',t.skill_level,
      'prize_info',t.prize_info,'venue',t.venue,'venue_address',t.venue_address,'maps_url',t.maps_url,
      'emirate',t.emirate,'registration_end',t.registration_end,'start_date',t.start_date,'end_date',t.end_date,
      'is_public',t.is_public,'share_code',t.share_code,'courts',t.courts,'updated_at',t.updated_at,
      'advance_per_group',t.advance_per_group,
      'winner_registration_id',t.winner_registration_id,'runner_up_registration_id',t.runner_up_registration_id,
      'third_registration_id',t.third_registration_id,
      'winner_team_name',wr.team_name,'runner_up_team_name',rr.team_name,'third_team_name',thr.team_name,
      'cover_photo_url',t.cover_photo_url,'group_photo_url',t.group_photo_url),
    'can_manage', COALESCE(_can_manage_tournament(v_tid), false),
    'my_registration', (
      SELECT jsonb_build_object('id',tr.id,'team_name',tr.team_name,'status',tr.status,'payment_status',tr.payment_status)
      FROM tournament_registrations tr
      WHERE tr.tournament_id=v_tid AND tr.registered_by = auth.uid() AND tr.status <> 'withdrawn'
      ORDER BY tr.created_at LIMIT 1),
    'teams', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'team_name',tr.team_name,
                 'player_a_name',tr.player_a_name,'player_b_name',tr.player_b_name,'seed',tr.seed)
               ORDER BY COALESCE(tr.seed,9999), tr.created_at)
             FROM tournament_registrations tr WHERE tr.tournament_id=v_tid AND tr.status='confirmed'),'[]'),
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'id',tm.id,'round',tm.round,'position',tm.position,
          'team_a_id',tm.team_a_id,'team_a_name',ta.team_name,
          'team_b_id',tm.team_b_id,'team_b_name',tb.team_name,
          'score_a',tm.score_a,'score_b',tm.score_b,'games',tm.games,
          'winner_id',tm.winner_id,'winner_name',tw.team_name,
          'status',tm.status,'next_match_id',tm.next_match_id,'court',tm.court,
          'stage',tm.stage,'group_label',tm.group_label)
        ORDER BY tm.round, tm.position)
      FROM tournament_matches tm
      LEFT JOIN tournament_registrations ta ON ta.id=tm.team_a_id
      LEFT JOIN tournament_registrations tb ON tb.id=tm.team_b_id
      LEFT JOIN tournament_registrations tw ON tw.id=tm.winner_id
      WHERE tm.tournament_id=v_tid), '[]'),
    'standings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'registration_id',vs.registration_id,'team_name',vs.team_name,'seed',vs.seed,
          'wins',vs.wins,'losses',vs.losses,'played',vs.played,'sets_for',vs.sets_for,'sets_against',vs.sets_against)
        ORDER BY vs.wins DESC, (vs.sets_for - vs.sets_against) DESC)
      FROM v_tournament_standings vs WHERE vs.tournament_id=v_tid), '[]'),
    'photos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',tp.id,'url',tp.url,'thumb_url',tp.thumb_url,'caption',tp.caption,'kind',tp.kind)
             ORDER BY tp.created_at)
      FROM tournament_photos tp WHERE tp.tournament_id=v_tid), '[]'),
    'confirmed_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='confirmed'),
    'pending_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='pending'),
    'waitlist_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='waitlisted')
  ) INTO v
  FROM tournaments t JOIN clubs c ON c.id=t.club_id
  LEFT JOIN tournament_registrations wr  ON wr.id  = t.winner_registration_id
  LEFT JOIN tournament_registrations rr  ON rr.id  = t.runner_up_registration_id
  LEFT JOIN tournament_registrations thr ON thr.id = t.third_registration_id
  WHERE t.id=v_tid;
  RETURN v;
END;$$;

-- get_tournament_detail: expose currency, waitlisted registrations, and match games.
CREATE OR REPLACE FUNCTION public.get_tournament_detail(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_result jsonb; v_mgr boolean;
BEGIN
  v_mgr := COALESCE(_can_manage_tournament(p_tournament_id), false);
  SELECT jsonb_build_object(
    'tournament', to_jsonb(t) || jsonb_build_object('club_name', c.name, 'winner_team_name', wr.team_name,
                    'currency', COALESCE(t.currency, c.currency, 'AED')),
    'can_manage', v_mgr,
    'registrations', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'id', tr.id, 'team_name', tr.team_name,
          'player_a_name', tr.player_a_name, 'player_b_name', tr.player_b_name,
          'status', tr.status, 'seed', tr.seed,
          'payment_status', CASE WHEN v_mgr THEN tr.payment_status ELSE NULL END,
          'contact_phone',  CASE WHEN v_mgr THEN tr.contact_phone ELSE NULL END,
          'registered_by', tr.registered_by, 'created_at', tr.created_at)
        ORDER BY COALESCE(tr.seed, 9999), tr.created_at)
      FROM tournament_registrations tr
      WHERE tr.tournament_id = p_tournament_id AND tr.status IN ('pending','confirmed','waitlisted')
    ), '[]'),
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'id', tm.id, 'round', tm.round, 'position', tm.position,
          'team_a_id', tm.team_a_id, 'team_a_name', ta.team_name,
          'team_b_id', tm.team_b_id, 'team_b_name', tb.team_name,
          'score_a', tm.score_a, 'score_b', tm.score_b, 'games', tm.games,
          'winner_id', tm.winner_id, 'winner_name', tw.team_name,
          'status', tm.status, 'next_match_id', tm.next_match_id,
          'next_match_slot', tm.next_match_slot, 'scheduled_at', tm.scheduled_at,
          'court', tm.court, 'stage', tm.stage, 'group_label', tm.group_label)
        ORDER BY tm.round, tm.position)
      FROM tournament_matches tm
      LEFT JOIN tournament_registrations ta ON ta.id = tm.team_a_id
      LEFT JOIN tournament_registrations tb ON tb.id = tm.team_b_id
      LEFT JOIN tournament_registrations tw ON tw.id = tm.winner_id
      WHERE tm.tournament_id = p_tournament_id
    ), '[]'),
    'standings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'registration_id', vs.registration_id, 'team_name', vs.team_name, 'seed', vs.seed,
          'wins', vs.wins, 'losses', vs.losses, 'played', vs.played,
          'sets_for', vs.sets_for, 'sets_against', vs.sets_against)
        ORDER BY vs.wins DESC, (vs.sets_for - vs.sets_against) DESC)
      FROM v_tournament_standings vs WHERE vs.tournament_id = p_tournament_id
    ), '[]'),
    'photos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',tp.id,'url',tp.url,'thumb_url',tp.thumb_url,'caption',tp.caption,'kind',tp.kind)
             ORDER BY tp.created_at)
      FROM tournament_photos tp WHERE tp.tournament_id = p_tournament_id
    ), '[]')
  ) INTO v_result
  FROM tournaments t
  JOIN clubs c ON c.id = t.club_id
  LEFT JOIN tournament_registrations wr ON wr.id = t.winner_registration_id
  WHERE t.id = p_tournament_id;
  IF v_result IS NULL THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  RETURN v_result;
END;$$;;
