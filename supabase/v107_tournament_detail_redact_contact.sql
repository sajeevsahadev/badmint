-- v107_tournament_detail_redact_contact
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- get_tournament_detail powers both the public /tournament/:id page and the
-- director panel. Registrant contact_phone / payment_status must only reach a
-- tournament manager, never the public. Redact them for non-managers.
CREATE OR REPLACE FUNCTION public.get_tournament_detail(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_result jsonb; v_mgr boolean;
BEGIN
  v_mgr := COALESCE(_can_manage_tournament(p_tournament_id), false);

  SELECT jsonb_build_object(
    'tournament', to_jsonb(t) || jsonb_build_object('club_name', c.name, 'winner_team_name', wr.team_name),
    'can_manage', v_mgr,
    'registrations', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'id', tr.id, 'team_name', tr.team_name,
          'player_a_name', tr.player_a_name, 'player_b_name', tr.player_b_name,
          'status', tr.status, 'seed', tr.seed,
          'payment_status', CASE WHEN v_mgr THEN tr.payment_status ELSE NULL END,
          'contact_phone',  CASE WHEN v_mgr THEN tr.contact_phone ELSE NULL END,
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
END;
$$;;
