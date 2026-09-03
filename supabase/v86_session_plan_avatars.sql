-- v86_session_plan_avatars
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Add avatar_url to the game-plan player map so the UI can show faces.
CREATE OR REPLACE FUNCTION public.get_session_plan(p_schedule_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_club_id uuid; v_plan session_plans;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF v_club_id IS NULL THEN RETURN NULL; END IF;
  IF NOT EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = v_club_id AND cm.user_id = auth.uid()) THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_plan FROM session_plans WHERE schedule_id = p_schedule_id;
  IF v_plan.id IS NULL THEN RETURN NULL; END IF;

  RETURN jsonb_build_object(
    'plan', jsonb_build_object('id', v_plan.id, 'courts', v_plan.courts,
              'match_count', v_plan.match_count, 'format', v_plan.format, 'version', v_plan.version),
    'matches', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', spm.id, 'round', spm.round, 'court', spm.court, 'seq', spm.seq,
        'side_a', to_jsonb(spm.side_a), 'side_b', to_jsonb(spm.side_b),
        'status', spm.status, 'match_id', spm.match_id) ORDER BY spm.seq)
      FROM session_plan_matches spm WHERE spm.plan_id = v_plan.id), '[]'::jsonb),
    'players', COALESCE((SELECT jsonb_object_agg(p.id, jsonb_build_object(
        'name', COALESCE(up.nickname, p.display_name), 'elo', round(p.elo)::int,
        'avatar', up.avatar_url))
      FROM players p LEFT JOIN user_profiles up ON up.user_id = p.user_id
      WHERE p.club_id = v_club_id AND p.is_active), '{}'::jsonb)
  );
END; $$;;
