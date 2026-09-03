-- v85_session_game_plan
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Session game plan (friendly fair-rotation, Phase 1).
-- One plan per club_schedule; matches generated client-side and persisted here
-- so every member of that day sees the same plan (realtime).

CREATE TABLE IF NOT EXISTS session_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id uuid NOT NULL REFERENCES club_schedule(id) ON DELETE CASCADE,
  club_id uuid NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  courts int NOT NULL DEFAULT 1,
  match_count int NOT NULL DEFAULT 6,
  format text NOT NULL DEFAULT 'friendly',
  version int NOT NULL DEFAULT 1,
  created_by uuid REFERENCES auth.users,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (schedule_id)
);

CREATE TABLE IF NOT EXISTS session_plan_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES session_plans(id) ON DELETE CASCADE,
  round int NOT NULL,
  court int NOT NULL DEFAULT 1,
  seq int NOT NULL,
  side_a uuid[] NOT NULL,
  side_b uuid[] NOT NULL,
  status text NOT NULL DEFAULT 'planned',   -- planned | done | skipped
  match_id uuid REFERENCES matches(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_spm_plan ON session_plan_matches(plan_id);

ALTER TABLE session_plans        ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_plan_matches ENABLE ROW LEVEL SECURITY;

-- Members of the club may READ the plan (so realtime works); writes go only
-- through the SECURITY DEFINER RPCs below (manager-gated).
DROP POLICY IF EXISTS sp_member_read ON session_plans;
CREATE POLICY sp_member_read ON session_plans FOR SELECT USING (
  EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = session_plans.club_id AND cm.user_id = auth.uid())
);
DROP POLICY IF EXISTS spm_member_read ON session_plan_matches;
CREATE POLICY spm_member_read ON session_plan_matches FOR SELECT USING (
  EXISTS (SELECT 1 FROM session_plans sp JOIN club_members cm ON cm.club_id = sp.club_id
          WHERE sp.id = session_plan_matches.plan_id AND cm.user_id = auth.uid())
);

-- realtime
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE session_plan_matches;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE session_plans;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;

-- ── helper: is caller a manager/owner of this club (or app admin) ──
CREATE OR REPLACE FUNCTION public._is_club_manager(p_club_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (
    SELECT 1 FROM club_members cm
    WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid() AND cm.role IN ('owner','manager')
  ) OR public.is_app_admin();
$$;

-- ── save/replace the whole plan (initial generate + regenerate) ──
CREATE OR REPLACE FUNCTION public.save_session_plan(
  p_schedule_id uuid, p_courts int, p_match_count int, p_matches jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_club_id uuid; v_plan_id uuid; m jsonb;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF v_club_id IS NULL THEN RAISE EXCEPTION 'Schedule not found'; END IF;
  IF NOT public._is_club_manager(v_club_id) THEN
    RAISE EXCEPTION 'Only managers can generate the game plan';
  END IF;

  INSERT INTO session_plans(schedule_id, club_id, courts, match_count, format, created_by)
    VALUES (p_schedule_id, v_club_id, greatest(p_courts,1), greatest(p_match_count,1), 'friendly', auth.uid())
  ON CONFLICT (schedule_id) DO UPDATE
    SET courts = excluded.courts, match_count = excluded.match_count,
        version = session_plans.version + 1, updated_at = now()
  RETURNING id INTO v_plan_id;

  DELETE FROM session_plan_matches WHERE plan_id = v_plan_id;
  FOR m IN SELECT * FROM jsonb_array_elements(p_matches) LOOP
    INSERT INTO session_plan_matches(plan_id, round, court, seq, side_a, side_b, status, match_id)
    VALUES (
      v_plan_id,
      (m->>'round')::int, (m->>'court')::int, (m->>'seq')::int,
      (SELECT array_agg(x::uuid) FROM jsonb_array_elements_text(m->'side_a') x),
      (SELECT array_agg(x::uuid) FROM jsonb_array_elements_text(m->'side_b') x),
      COALESCE(m->>'status', 'planned'),
      NULLIF(m->>'match_id', '')::uuid
    );
  END LOOP;
  RETURN v_plan_id;
END; $$;

-- ── read the plan (any member) with resolved player names ──
CREATE OR REPLACE FUNCTION public.get_session_plan(p_schedule_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_club_id uuid; v_plan session_plans;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF v_club_id IS NULL THEN RETURN NULL; END IF;
  IF NOT EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = v_club_id AND cm.user_id = auth.uid()) THEN
    RETURN NULL;   -- members only
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
        'name', COALESCE(up.nickname, p.display_name), 'elo', p.elo))
      FROM players p LEFT JOIN user_profiles up ON up.user_id = p.user_id
      WHERE p.club_id = v_club_id AND p.is_active), '{}'::jsonb)
  );
END; $$;

-- ── swap players in one planned match (manager; drag/tap-to-swap) ──
CREATE OR REPLACE FUNCTION public.update_plan_match(
  p_plan_match_id uuid, p_side_a uuid[], p_side_b uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_club_id uuid; v_plan_id uuid;
BEGIN
  SELECT sp.club_id, sp.id INTO v_club_id, v_plan_id
  FROM session_plan_matches spm JOIN session_plans sp ON sp.id = spm.plan_id
  WHERE spm.id = p_plan_match_id;
  IF v_club_id IS NULL THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF NOT public._is_club_manager(v_club_id) THEN RAISE EXCEPTION 'Only managers can edit the game plan'; END IF;
  UPDATE session_plan_matches SET side_a = p_side_a, side_b = p_side_b WHERE id = p_plan_match_id;
  UPDATE session_plans SET updated_at = now() WHERE id = v_plan_id;
END; $$;

-- ── mark a planned match done/skipped, link the recorded match (manager) ──
CREATE OR REPLACE FUNCTION public.set_plan_match_status(
  p_plan_match_id uuid, p_status text, p_match_id uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_club_id uuid;
BEGIN
  SELECT sp.club_id INTO v_club_id
  FROM session_plan_matches spm JOIN session_plans sp ON sp.id = spm.plan_id
  WHERE spm.id = p_plan_match_id;
  IF v_club_id IS NULL THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF NOT public._is_club_manager(v_club_id) THEN RAISE EXCEPTION 'Only managers can edit the game plan'; END IF;
  UPDATE session_plan_matches
    SET status = p_status, match_id = COALESCE(p_match_id, match_id)
    WHERE id = p_plan_match_id;
END; $$;

-- ── clear the plan (manager) ──
CREATE OR REPLACE FUNCTION public.delete_session_plan(p_schedule_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_club_id uuid;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF v_club_id IS NULL THEN RETURN; END IF;
  IF NOT public._is_club_manager(v_club_id) THEN RAISE EXCEPTION 'Only managers can clear the game plan'; END IF;
  DELETE FROM session_plans WHERE schedule_id = p_schedule_id;
END; $$;

GRANT EXECUTE ON FUNCTION public.save_session_plan(uuid,int,int,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_session_plan(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_plan_match(uuid,uuid[],uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_plan_match_status(uuid,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_session_plan(uuid) TO authenticated;;
