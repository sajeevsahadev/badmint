-- v105_tournament_public_live_and_photos
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- ═══════════════════════════════════════════════════════════════════════
-- v105: Public live tournament page (matches + standings + podium names +
-- photos), photo gallery RPCs, cover/group media, and realtime.
-- ═══════════════════════════════════════════════════════════════════════

-- Public tournament payload, now with live matches, standings, podium names & photos.
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
      'id',t.id,'name',t.name,'club_id',t.club_id,'club_name',c.name,'description',t.description,
      'draw_type',t.draw_type,'status',t.status,'max_teams',t.max_teams,'entry_fee',t.entry_fee,
      'prize_info',t.prize_info,'venue',t.venue,'venue_address',t.venue_address,'maps_url',t.maps_url,
      'emirate',t.emirate,'registration_end',t.registration_end,'start_date',t.start_date,'end_date',t.end_date,
      'is_public',t.is_public,'share_code',t.share_code,'courts',t.courts,'updated_at',t.updated_at,
      'winner_registration_id',t.winner_registration_id,'runner_up_registration_id',t.runner_up_registration_id,
      'third_registration_id',t.third_registration_id,
      'winner_team_name',wr.team_name,'runner_up_team_name',rr.team_name,'third_team_name',thr.team_name,
      'cover_photo_url',t.cover_photo_url,'group_photo_url',t.group_photo_url),
    'teams', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'team_name',tr.team_name,
                 'player_a_name',tr.player_a_name,'player_b_name',tr.player_b_name,'seed',tr.seed)
               ORDER BY COALESCE(tr.seed,9999), tr.created_at)
             FROM tournament_registrations tr WHERE tr.tournament_id=v_tid AND tr.status='confirmed'),'[]'),
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'id',tm.id,'round',tm.round,'position',tm.position,
          'team_a_id',tm.team_a_id,'team_a_name',ta.team_name,
          'team_b_id',tm.team_b_id,'team_b_name',tb.team_name,
          'score_a',tm.score_a,'score_b',tm.score_b,'winner_id',tm.winner_id,'winner_name',tw.team_name,
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
          'wins',vs.wins,'losses',vs.losses,'played',vs.played,
          'sets_for',vs.sets_for,'sets_against',vs.sets_against)
        ORDER BY vs.wins DESC, (vs.sets_for - vs.sets_against) DESC)
      FROM v_tournament_standings vs WHERE vs.tournament_id=v_tid), '[]'),
    'photos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',tp.id,'url',tp.url,'caption',tp.caption,'kind',tp.kind)
             ORDER BY tp.created_at)
      FROM tournament_photos tp WHERE tp.tournament_id=v_tid), '[]'),
    'confirmed_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='confirmed'),
    'pending_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='pending')
  ) INTO v
  FROM tournaments t JOIN clubs c ON c.id=t.club_id
  LEFT JOIN tournament_registrations wr  ON wr.id  = t.winner_registration_id
  LEFT JOIN tournament_registrations rr  ON rr.id  = t.runner_up_registration_id
  LEFT JOIN tournament_registrations thr ON thr.id = t.third_registration_id
  WHERE t.id=v_tid;
  RETURN v;
END;$$;

-- Director detail: add photos array (append to the existing payload shape).
CREATE OR REPLACE FUNCTION public.get_tournament_detail(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tournament', to_jsonb(t) || jsonb_build_object('club_name', c.name, 'winner_team_name', wr.team_name),
    'registrations', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'id', tr.id, 'team_name', tr.team_name,
          'player_a_name', tr.player_a_name, 'player_b_name', tr.player_b_name,
          'status', tr.status, 'seed', tr.seed, 'payment_status', tr.payment_status,
          'contact_phone', tr.contact_phone,
          'registered_by', tr.registered_by, 'created_at', tr.created_at
        ) ORDER BY COALESCE(tr.seed, 9999), tr.created_at)
      FROM tournament_registrations tr
      WHERE tr.tournament_id = p_tournament_id AND tr.status IN ('pending','confirmed')
    ), '[]'),
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'id', tm.id, 'round', tm.round, 'position', tm.position,
          'team_a_id', tm.team_a_id, 'team_a_name', ta.team_name,
          'team_b_id', tm.team_b_id, 'team_b_name', tb.team_name,
          'score_a', tm.score_a, 'score_b', tm.score_b,
          'winner_id', tm.winner_id, 'winner_name', tw.team_name,
          'status', tm.status, 'next_match_id', tm.next_match_id,
          'next_match_slot', tm.next_match_slot, 'scheduled_at', tm.scheduled_at,
          'court', tm.court, 'stage', tm.stage, 'group_label', tm.group_label
        ) ORDER BY tm.round, tm.position)
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
          'sets_for', vs.sets_for, 'sets_against', vs.sets_against
        ) ORDER BY vs.wins DESC, (vs.sets_for - vs.sets_against) DESC)
      FROM v_tournament_standings vs WHERE vs.tournament_id = p_tournament_id
    ), '[]'),
    'photos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',tp.id,'url',tp.url,'caption',tp.caption,'kind',tp.kind)
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
END;$$;

-- ── Photo gallery RPCs (paste-URL, consistent with facilities image_url) ──
CREATE OR REPLACE FUNCTION public.add_tournament_photo(
  p_tournament_id uuid, p_url text, p_caption text DEFAULT NULL, p_kind text DEFAULT 'gallery')
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF COALESCE(trim(p_url),'') = '' THEN RAISE EXCEPTION 'Photo URL required'; END IF;
  INSERT INTO tournament_photos (tournament_id, url, caption, kind, created_by)
  VALUES (p_tournament_id, trim(p_url), NULLIF(trim(p_caption),''), COALESCE(NULLIF(p_kind,''),'gallery'), auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;$$;

CREATE OR REPLACE FUNCTION public.delete_tournament_photo(p_photo_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_tid uuid;
BEGIN
  SELECT tournament_id INTO v_tid FROM tournament_photos WHERE id = p_photo_id;
  IF v_tid IS NULL THEN RETURN; END IF;
  IF NOT _can_manage_tournament(v_tid) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  DELETE FROM tournament_photos WHERE id = p_photo_id;
END;$$;

CREATE OR REPLACE FUNCTION public.set_tournament_media(
  p_tournament_id uuid, p_cover_url text DEFAULT NULL, p_group_url text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE tournaments
     SET cover_photo_url = NULLIF(trim(COALESCE(p_cover_url,'')),''),
         group_photo_url = NULLIF(trim(COALESCE(p_group_url,'')),''),
         updated_at = now()
   WHERE id = p_tournament_id;
END;$$;

GRANT EXECUTE ON FUNCTION public.add_tournament_photo(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_tournament_photo(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_tournament_media(uuid,text,text) TO authenticated;

-- ── Realtime: director panel subscribes to live match/tournament changes ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname='supabase_realtime' AND tablename='tournament_matches') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_matches;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname='supabase_realtime' AND tablename='tournaments') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tournaments;
  END IF;
END$$;
;
