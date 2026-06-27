-- v42: Fix finish_live_match to record correct point score for multi-game matches.
-- Bug: when score_a/score_b were 0-0 (reset after game win), the function passed
-- games_a/games_b (e.g. 0, 1) as the score to record_match, resulting in "0 - 1"
-- in match history. Fix: use the last completed game's actual point score from
-- game_scores jsonb array. game_scores format: [{a:21,b:15},{a:13,b:21}, ...]

CREATE OR REPLACE FUNCTION finish_live_match(
  p_live_match_id uuid,
  p_display_name  text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_row       live_matches%ROWTYPE;
  v_role      text;
  v_match_id  uuid;
  v_final_a   int;
  v_final_b   int;
  v_last_game jsonb;
BEGIN
  SELECT * INTO v_row FROM live_matches WHERE id = p_live_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Live match not found'; END IF;
  IF v_row.status <> 'active' THEN RAISE EXCEPTION 'Match already finished or cancelled'; END IF;

  SELECT role INTO v_role FROM club_members
  WHERE club_id = v_row.club_id AND user_id = auth.uid();
  IF v_role NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Only managers can finish a match';
  END IF;

  IF v_row.score_a = 0 AND v_row.score_b = 0 AND jsonb_array_length(v_row.game_scores) > 0 THEN
    -- Scores reset after last game won — use the final game's actual point score
    v_last_game := v_row.game_scores->(jsonb_array_length(v_row.game_scores) - 1);
    v_final_a   := (v_last_game->>'a')::int;
    v_final_b   := (v_last_game->>'b')::int;
  ELSE
    -- Single game or mid-game finish — use current live scores
    v_final_a := v_row.score_a;
    v_final_b := v_row.score_b;
  END IF;

  IF v_final_a = v_final_b THEN
    RAISE EXCEPTION 'Cannot finish: scores are equal (% – %)', v_final_a, v_final_b;
  END IF;

  SELECT record_match(
    v_row.club_id,
    v_row.played_on,
    v_row.side_a,
    v_row.side_b,
    v_final_a,
    v_final_b,
    p_display_name
  ) INTO v_match_id;

  UPDATE live_matches
  SET status = 'finished', finished_at = now(), match_id = v_match_id
  WHERE id = p_live_match_id;

  RETURN v_match_id;
END;
$$;

GRANT EXECUTE ON FUNCTION finish_live_match(uuid, text) TO authenticated;
