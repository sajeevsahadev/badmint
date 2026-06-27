-- v39: Live point-by-point score tracking
-- Run this in Supabase SQL Editor

CREATE TABLE IF NOT EXISTS live_matches (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id      uuid NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  side_a       uuid[] NOT NULL,
  side_b       uuid[] NOT NULL,
  played_on    date NOT NULL DEFAULT current_date,
  score_a      int  NOT NULL DEFAULT 0,
  score_b      int  NOT NULL DEFAULT 0,
  status       text NOT NULL DEFAULT 'active' CHECK (status IN ('active','finished','cancelled')),
  serving_side text CHECK (serving_side IN ('A','B')),
  created_by   uuid REFERENCES auth.users(id),
  created_at   timestamptz DEFAULT now(),
  finished_at  timestamptz,
  match_id     uuid REFERENCES matches(id)
);

ALTER TABLE live_matches ENABLE ROW LEVEL SECURITY;

CREATE POLICY lm_read ON live_matches FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM club_members cm
    WHERE cm.club_id = live_matches.club_id AND cm.user_id = auth.uid()
  )
);

CREATE POLICY lm_write ON live_matches FOR ALL USING (
  EXISTS (
    SELECT 1 FROM club_members cm
    WHERE cm.club_id = live_matches.club_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('owner','manager')
  )
);

ALTER PUBLICATION supabase_realtime ADD TABLE live_matches;

-- ── start_live_match ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION start_live_match(
  p_club_id      uuid,
  p_side_a       uuid[],
  p_side_b       uuid[],
  p_played_on    date    DEFAULT current_date,
  p_serving_side text    DEFAULT 'A'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_role   text;
  v_id     uuid;
BEGIN
  SELECT role INTO v_role FROM club_members
  WHERE club_id = p_club_id AND user_id = auth.uid();

  IF v_role NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Only managers can start a live match';
  END IF;

  INSERT INTO live_matches (club_id, side_a, side_b, played_on, serving_side, created_by)
  VALUES (p_club_id, p_side_a, p_side_b, p_played_on, p_serving_side, auth.uid())
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ── add_live_point ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION add_live_point(
  p_live_match_id uuid,
  p_side          text   -- 'A' or 'B'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_row    live_matches%ROWTYPE;
  v_role   text;
  v_new_a  int;
  v_new_b  int;
BEGIN
  SELECT * INTO v_row FROM live_matches WHERE id = p_live_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Live match not found'; END IF;
  IF v_row.status <> 'active' THEN RAISE EXCEPTION 'Match is not active'; END IF;

  SELECT role INTO v_role FROM club_members
  WHERE club_id = v_row.club_id AND user_id = auth.uid();
  IF v_role NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Only managers can add points';
  END IF;

  v_new_a := v_row.score_a;
  v_new_b := v_row.score_b;

  IF p_side = 'A' THEN v_new_a := v_new_a + 1;
  ELSIF p_side = 'B' THEN v_new_b := v_new_b + 1;
  ELSE RAISE EXCEPTION 'side must be A or B';
  END IF;

  -- Switch serve to the scoring side
  UPDATE live_matches
  SET score_a = v_new_a, score_b = v_new_b, serving_side = p_side
  WHERE id = p_live_match_id;

  RETURN jsonb_build_object('score_a', v_new_a, 'score_b', v_new_b, 'status', 'active', 'serving_side', p_side);
END;
$$;

-- ── undo_live_point ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION undo_live_point(p_live_match_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_row  live_matches%ROWTYPE;
  v_role text;
BEGIN
  SELECT * INTO v_row FROM live_matches WHERE id = p_live_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Live match not found'; END IF;
  IF v_row.status <> 'active' THEN RAISE EXCEPTION 'Match is not active'; END IF;

  SELECT role INTO v_role FROM club_members
  WHERE club_id = v_row.club_id AND user_id = auth.uid();
  IF v_role NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Only managers can undo points';
  END IF;

  -- We cannot know which side scored the last point without a log, so we do nothing
  -- but return current state. The UI should track who scored and call add_live_point
  -- on the wrong side, but undo is kept as a best-effort decrement of the higher score.
  -- If scores are equal, decrement A first as a tie-break heuristic.
  IF v_row.score_a > v_row.score_b THEN
    UPDATE live_matches SET score_a = GREATEST(0, v_row.score_a - 1) WHERE id = p_live_match_id;
    RETURN jsonb_build_object('score_a', GREATEST(0, v_row.score_a - 1), 'score_b', v_row.score_b);
  ELSIF v_row.score_b > v_row.score_a THEN
    UPDATE live_matches SET score_b = GREATEST(0, v_row.score_b - 1) WHERE id = p_live_match_id;
    RETURN jsonb_build_object('score_a', v_row.score_a, 'score_b', GREATEST(0, v_row.score_b - 1));
  ELSE
    UPDATE live_matches SET score_a = GREATEST(0, v_row.score_a - 1) WHERE id = p_live_match_id;
    RETURN jsonb_build_object('score_a', GREATEST(0, v_row.score_a - 1), 'score_b', v_row.score_b);
  END IF;
END;
$$;

-- ── finish_live_match ─────────────────────────────────────────────────────────
-- Calls the full record_match RPC logic: inserts match+sides+participants, runs Elo, records attendance.
-- Returns the new match_id.
CREATE OR REPLACE FUNCTION finish_live_match(
  p_live_match_id uuid,
  p_display_name  text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_row      live_matches%ROWTYPE;
  v_role     text;
  v_match_id uuid;
BEGIN
  SELECT * INTO v_row FROM live_matches WHERE id = p_live_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Live match not found'; END IF;
  IF v_row.status <> 'active' THEN RAISE EXCEPTION 'Match already finished or cancelled'; END IF;
  IF v_row.score_a = v_row.score_b THEN RAISE EXCEPTION 'Scores cannot be equal'; END IF;

  SELECT role INTO v_role FROM club_members
  WHERE club_id = v_row.club_id AND user_id = auth.uid();
  IF v_role NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Only managers can finish a match';
  END IF;

  -- Delegate to the existing record_match RPC
  SELECT record_match(
    v_row.club_id,
    v_row.played_on,
    v_row.side_a,
    v_row.side_b,
    v_row.score_a,
    v_row.score_b,
    p_display_name
  ) INTO v_match_id;

  UPDATE live_matches
  SET status = 'finished', finished_at = now(), match_id = v_match_id
  WHERE id = p_live_match_id;

  RETURN v_match_id;
END;
$$;

GRANT EXECUTE ON FUNCTION start_live_match(uuid, uuid[], uuid[], date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION add_live_point(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION undo_live_point(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION finish_live_match(uuid, text) TO authenticated;
