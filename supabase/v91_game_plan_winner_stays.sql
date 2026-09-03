-- v91_game_plan_winner_stays
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Winner-stays support for the session game plan.
-- state jsonb holds the live winner-stays queue + per-court win streaks.
ALTER TABLE session_plans ADD COLUMN IF NOT EXISTS state jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE session_plan_matches ADD COLUMN IF NOT EXISTS winner_side text;  -- 'A' | 'B' | null

-- Extend save_session_plan to persist format + state. (Drop/recreate because the
-- signature gains parameters; callers use named args so this is safe.)
DROP FUNCTION IF EXISTS public.save_session_plan(uuid, int, int, jsonb);
CREATE OR REPLACE FUNCTION public.save_session_plan(
  p_schedule_id uuid, p_courts int, p_match_count int, p_matches jsonb,
  p_format text DEFAULT 'friendly', p_state jsonb DEFAULT '{}'::jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_club_id uuid; v_plan_id uuid; m jsonb;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF v_club_id IS NULL THEN RAISE EXCEPTION 'Schedule not found'; END IF;
  IF NOT public._is_club_manager(v_club_id) THEN
    RAISE EXCEPTION 'Only managers can generate the game plan';
  END IF;

  INSERT INTO session_plans(schedule_id, club_id, courts, match_count, format, state, created_by)
    VALUES (p_schedule_id, v_club_id, greatest(p_courts,1), greatest(p_match_count,1),
            COALESCE(p_format,'friendly'), COALESCE(p_state,'{}'::jsonb), auth.uid())
  ON CONFLICT (schedule_id) DO UPDATE
    SET courts = excluded.courts, match_count = excluded.match_count,
        format = excluded.format, state = excluded.state,
        version = session_plans.version + 1, updated_at = now()
  RETURNING id INTO v_plan_id;

  DELETE FROM session_plan_matches WHERE plan_id = v_plan_id;
  FOR m IN SELECT * FROM jsonb_array_elements(p_matches) LOOP
    INSERT INTO session_plan_matches(plan_id, round, court, seq, side_a, side_b, status, match_id, winner_side)
    VALUES (
      v_plan_id,
      (m->>'round')::int, (m->>'court')::int, (m->>'seq')::int,
      (SELECT array_agg(x::uuid) FROM jsonb_array_elements_text(m->'side_a') x),
      (SELECT array_agg(x::uuid) FROM jsonb_array_elements_text(m->'side_b') x),
      COALESCE(m->>'status', 'planned'),
      NULLIF(m->>'match_id', '')::uuid,
      NULLIF(m->>'winner_side', '')
    );
  END LOOP;
  RETURN v_plan_id;
END; $$;
GRANT EXECUTE ON FUNCTION public.save_session_plan(uuid,int,int,jsonb,text,jsonb) TO authenticated;

-- get_session_plan: include format, state, and per-match winner_side.
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
              'match_count', v_plan.match_count, 'format', v_plan.format,
              'version', v_plan.version, 'state', v_plan.state),
    'matches', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', spm.id, 'round', spm.round, 'court', spm.court, 'seq', spm.seq,
        'side_a', to_jsonb(spm.side_a), 'side_b', to_jsonb(spm.side_b),
        'status', spm.status, 'match_id', spm.match_id, 'winner_side', spm.winner_side) ORDER BY spm.seq)
      FROM session_plan_matches spm WHERE spm.plan_id = v_plan.id), '[]'::jsonb),
    'players', COALESCE((SELECT jsonb_object_agg(p.id, jsonb_build_object(
        'name', COALESCE(up.nickname, p.display_name), 'elo', round(p.elo)::int,
        'avatar', up.avatar_url))
      FROM players p LEFT JOIN user_profiles up ON up.user_id = p.user_id
      WHERE p.club_id = v_club_id AND p.is_active), '{}'::jsonb)
  );
END; $$;;
