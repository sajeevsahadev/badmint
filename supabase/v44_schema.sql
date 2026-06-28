-- v44: Simplify live scoring to single-game only.
-- Remove multi-game reset logic from add_live_point_v2.
-- Once a side reaches winning score the RPC returns match_won:true and the
-- UI prompts to record. No more game resets or current_game increments.

CREATE OR REPLACE FUNCTION add_live_point_v2(
  p_live_match_id    uuid,
  p_scored_by_player uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_row      live_matches%ROWTYPE;
  v_role     text;
  v_side     text;
  v_new_a    int;
  v_new_b    int;
  v_won      boolean := false;
  v_winner   text;
  v_new_srv  uuid;
  v_srv_side text;
BEGIN
  SELECT * INTO v_row FROM live_matches WHERE id = p_live_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Live match not found'; END IF;
  IF v_row.status <> 'active' THEN RAISE EXCEPTION 'Match is not active'; END IF;

  SELECT role INTO v_role FROM club_members
  WHERE club_id = v_row.club_id AND user_id = auth.uid();
  IF v_role NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Only managers can score points';
  END IF;

  -- Determine side of scoring player
  IF p_scored_by_player = ANY(v_row.side_a) THEN
    v_side := 'A';
  ELSIF p_scored_by_player = ANY(v_row.side_b) THEN
    v_side := 'B';
  ELSE
    RAISE EXCEPTION 'Player is not in this match';
  END IF;

  v_new_a := v_row.score_a;
  v_new_b := v_row.score_b;

  -- Cap at 30 (deuce cap)
  IF v_side = 'A' THEN
    IF v_row.score_a >= 30 THEN RAISE EXCEPTION 'Score cannot exceed 30'; END IF;
    v_new_a := v_new_a + 1;
  ELSE
    IF v_row.score_b >= 30 THEN RAISE EXCEPTION 'Score cannot exceed 30'; END IF;
    v_new_b := v_new_b + 1;
  END IF;

  -- Serve rotation: scorer's side retains/gains serve
  v_srv_side := v_side;
  IF v_side = 'A' THEN
    v_new_srv := p_scored_by_player;
  ELSE
    v_new_srv := p_scored_by_player;
  END IF;

  -- Win detection: ≥21 with 2-point lead, or exactly 30
  IF (v_new_a >= 21 AND v_new_a - v_new_b >= 2) OR v_new_a = 30 THEN
    v_won := true; v_winner := 'A';
  ELSIF (v_new_b >= 21 AND v_new_b - v_new_a >= 2) OR v_new_b = 30 THEN
    v_won := true; v_winner := 'B';
  END IF;

  UPDATE live_matches
  SET score_a        = v_new_a,
      score_b        = v_new_b,
      serving_player = v_new_srv,
      serving_side   = v_srv_side
  WHERE id = p_live_match_id;

  -- Log the point
  INSERT INTO live_match_points
    (live_match_id, game_number, scored_by, side, server_player, server_side, score_a_after, score_b_after)
  VALUES
    (p_live_match_id, 1, p_scored_by_player, v_side, v_new_srv, v_srv_side, v_new_a, v_new_b);

  RETURN jsonb_build_object(
    'score_a',      v_new_a,
    'score_b',      v_new_b,
    'serving_side', v_srv_side,
    'serving_player', v_new_srv,
    'match_won',    v_won,
    'winner_side',  v_winner
  );
END;
$$;

-- Simplify finish_live_match: always use current score_a/score_b (single game)
CREATE OR REPLACE FUNCTION finish_live_match(
  p_live_match_id uuid,
  p_display_name  text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_row      live_matches%ROWTYPE;
  v_role     text;
  v_match_id uuid;
BEGIN
  SELECT * INTO v_row FROM live_matches WHERE id = p_live_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Live match not found'; END IF;
  IF v_row.status <> 'active' THEN RAISE EXCEPTION 'Match already finished or cancelled'; END IF;

  SELECT role INTO v_role FROM club_members
  WHERE club_id = v_row.club_id AND user_id = auth.uid();
  IF v_role NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Only managers can finish a match';
  END IF;

  IF v_row.score_a = v_row.score_b THEN
    RAISE EXCEPTION 'Scores are equal — cannot record a draw';
  END IF;

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

GRANT EXECUTE ON FUNCTION add_live_point_v2(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION finish_live_match(uuid, text)  TO authenticated;
