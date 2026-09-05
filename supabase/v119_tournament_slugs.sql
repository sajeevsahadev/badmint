-- v119_tournament_slugs
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS slug text;

CREATE OR REPLACE FUNCTION public._slugify(txt text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(
    NULLIF(trim(both '-' FROM regexp_replace(lower(txt), '[^a-z0-9]+', '-', 'g')), ''),
    'tournament');
$$;

CREATE OR REPLACE FUNCTION public._unique_tournament_slug(p_name text, p_id uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE base text := left(_slugify(p_name), 60); cand text; i int := 1;
BEGIN
  cand := base;
  WHILE EXISTS (SELECT 1 FROM tournaments WHERE slug = cand AND id <> COALESCE(p_id, '00000000-0000-0000-0000-000000000000')) LOOP
    i := i + 1; cand := base || '-' || i;
  END LOOP;
  RETURN cand;
END;$$;

CREATE OR REPLACE FUNCTION public._set_tournament_slug()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.slug IS NULL THEN NEW.slug := _unique_tournament_slug(NEW.name, NEW.id); END IF;
  RETURN NEW;
END;$$;

DROP TRIGGER IF EXISTS trg_set_tournament_slug ON public.tournaments;
CREATE TRIGGER trg_set_tournament_slug BEFORE INSERT ON public.tournaments
  FOR EACH ROW EXECUTE FUNCTION _set_tournament_slug();

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id, name FROM tournaments WHERE slug IS NULL ORDER BY created_at LOOP
    UPDATE tournaments SET slug = _unique_tournament_slug(r.name, r.id) WHERE id = r.id;
  END LOOP;
END$$;

CREATE UNIQUE INDEX IF NOT EXISTS tournaments_slug_key ON public.tournaments(slug);

CREATE OR REPLACE FUNCTION public.get_public_tournament(p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v jsonb; v_tid uuid;
BEGIN
  SELECT id INTO v_tid FROM tournaments WHERE slug = p_code OR share_code = p_code OR id::text = p_code LIMIT 1;
  IF v_tid IS NULL THEN RETURN NULL; END IF;
  SELECT jsonb_build_object(
    'tournament', jsonb_build_object(
      'id',t.id,'name',t.name,'slug',t.slug,'club_id',t.club_id,'club_name',c.name,
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

DROP FUNCTION IF EXISTS public.get_tournaments(uuid, text, text);
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
    AND (v_admin OR (t.status NOT IN ('draft','cancelled') AND t.is_public = true))
  ORDER BY CASE t.status WHEN 'live' THEN 1 WHEN 'registration_open' THEN 2 WHEN 'completed' THEN 3 ELSE 4 END,
    t.start_date DESC NULLS LAST, t.created_at DESC;
END;$$;
GRANT EXECUTE ON FUNCTION public.get_tournaments(uuid,text,text) TO anon, authenticated;;
