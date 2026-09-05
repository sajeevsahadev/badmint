-- v122_public_registration_fields
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- ═══════════════════════════════════════════════════════════════════════
-- v122: Google-Form-style registration — per-player contacts, a public insert
-- (called by the register-team Edge Function after the Turnstile check), and a
-- helper to fetch admin emails for the "new registration" notification.
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE public.tournament_registrations
  ADD COLUMN IF NOT EXISTS player_a_phone text,
  ADD COLUMN IF NOT EXISTS player_a_email text,
  ADD COLUMN IF NOT EXISTS player_b_phone text,
  ADD COLUMN IF NOT EXISTS player_b_email text;

-- Insert a public (anonymous) registration. Called with the service role from
-- the Edge Function AFTER Turnstile verification, so it trusts its inputs but
-- still enforces the tournament rules (open, deadline, capacity, no dup team).
CREATE OR REPLACE FUNCTION public.insert_public_registration(
  p_tournament_id uuid, p_team_name text,
  p_a_name text, p_a_phone text, p_a_email text,
  p_b_name text, p_b_phone text, p_b_email text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_tour record; v_count int; v_status text; v_id uuid; v_seq int; v_team text;
BEGIN
  SELECT * INTO v_tour FROM tournaments WHERE id = p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF v_tour.status <> 'registration_open' THEN RAISE EXCEPTION 'Registration is not open'; END IF;
  IF v_tour.registration_end IS NOT NULL AND v_tour.registration_end < current_date THEN
    RAISE EXCEPTION 'Registration has closed'; END IF;
  IF COALESCE(trim(p_a_name),'') = '' OR COALESCE(trim(p_b_name),'') = '' THEN
    RAISE EXCEPTION 'Both player names are required'; END IF;
  IF COALESCE(trim(p_a_email),'') = '' AND COALESCE(trim(p_b_email),'') = ''
     AND COALESCE(trim(p_a_phone),'') = '' AND COALESCE(trim(p_b_phone),'') = '' THEN
    RAISE EXCEPTION 'Please provide at least one email or phone number'; END IF;

  v_team := COALESCE(NULLIF(trim(p_team_name),''), trim(p_a_name) || ' & ' || trim(p_b_name));
  IF EXISTS (SELECT 1 FROM tournament_registrations
             WHERE tournament_id = p_tournament_id AND lower(team_name) = lower(v_team) AND status <> 'rejected') THEN
    v_team := v_team || ' (' || to_char(now(),'HH24MI') || ')';   -- avoid the unique-name clash
  END IF;

  SELECT COUNT(*) INTO v_count FROM tournament_registrations
   WHERE tournament_id = p_tournament_id AND status IN ('pending','confirmed');
  v_status := CASE WHEN v_count >= v_tour.max_teams THEN 'waitlisted' ELSE 'pending' END;

  INSERT INTO tournament_registrations
    (tournament_id, team_name, player_a_name, player_b_name,
     contact_phone, contact_email, player_a_phone, player_a_email, player_b_phone, player_b_email,
     registered_by, status, payment_status)
  VALUES (p_tournament_id, v_team, trim(p_a_name), trim(p_b_name),
     NULLIF(trim(p_a_phone),''), NULLIF(trim(p_a_email),''),
     NULLIF(trim(p_a_phone),''), NULLIF(trim(p_a_email),''),
     NULLIF(trim(p_b_phone),''), NULLIF(trim(p_b_email),''),
     NULL, v_status, 'pending')
  RETURNING id INTO v_id;

  SELECT COUNT(*) INTO v_seq FROM tournament_registrations
   WHERE tournament_id = p_tournament_id AND status <> 'rejected';
  RETURN jsonb_build_object('id', v_id, 'status', v_status, 'team_name', v_team, 'sequence', v_seq);
END;$$;

-- Admin emails + tournament name, for the "new registration" notification.
CREATE OR REPLACE FUNCTION public.get_tournament_admin_emails(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'name', (SELECT name FROM tournaments WHERE id = p_tournament_id),
    'slug', (SELECT slug FROM tournaments WHERE id = p_tournament_id),
    'emails', COALESCE((
      SELECT jsonb_agg(DISTINCT u.email)
      FROM tournament_admins ta JOIN auth.users u ON u.id = ta.user_id
      WHERE ta.tournament_id = p_tournament_id AND u.email IS NOT NULL), '[]'));
$$;

-- get_tournament_detail: expose per-player contacts to managers.
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
          'contact_email',  CASE WHEN v_mgr THEN tr.contact_email ELSE NULL END,
          'player_a_phone', CASE WHEN v_mgr THEN tr.player_a_phone ELSE NULL END,
          'player_a_email', CASE WHEN v_mgr THEN tr.player_a_email ELSE NULL END,
          'player_b_phone', CASE WHEN v_mgr THEN tr.player_b_phone ELSE NULL END,
          'player_b_email', CASE WHEN v_mgr THEN tr.player_b_email ELSE NULL END,
          'notes', CASE WHEN v_mgr THEN tr.notes ELSE NULL END,
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
