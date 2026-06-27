-- v41: Court-view live scoring — point log, serve tracking, multi-game

-- Point log table
CREATE TABLE IF NOT EXISTS live_match_points (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  live_match_id   uuid NOT NULL REFERENCES live_matches(id) ON DELETE CASCADE,
  game_number     int  NOT NULL DEFAULT 1,
  scored_by       uuid NOT NULL REFERENCES players(id),
  side            text NOT NULL CHECK (side IN ('A','B')),
  server_player   uuid REFERENCES players(id),
  server_side     text CHECK (server_side IN ('A','B')),
  score_a_after   int  NOT NULL,
  score_b_after   int  NOT NULL,
  created_at      timestamptz DEFAULT now()
);

ALTER TABLE live_match_points ENABLE ROW LEVEL SECURITY;

CREATE POLICY lmp_read  ON live_match_points FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM live_matches lm
    JOIN club_members cm ON cm.club_id = lm.club_id
    WHERE lm.id = live_match_points.live_match_id AND cm.user_id = auth.uid()
  )
);

CREATE POLICY lmp_write ON live_match_points FOR ALL USING (
  EXISTS (
    SELECT 1 FROM live_matches lm
    JOIN club_members cm ON cm.club_id = lm.club_id
    WHERE lm.id = live_match_points.live_match_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('owner','manager')
  )
);

ALTER PUBLICATION supabase_realtime ADD TABLE live_match_points;

-- New columns on live_matches
ALTER TABLE live_matches ADD COLUMN IF NOT EXISTS serving_player uuid REFERENCES players(id);
ALTER TABLE live_matches ADD COLUMN IF NOT EXISTS current_game   int  NOT NULL DEFAULT 1;
ALTER TABLE live_matches ADD COLUMN IF NOT EXISTS games_a        int  NOT NULL DEFAULT 0;
ALTER TABLE live_matches ADD COLUMN IF NOT EXISTS games_b        int  NOT NULL DEFAULT 0;
ALTER TABLE live_matches ADD COLUMN IF NOT EXISTS game_scores    jsonb NOT NULL DEFAULT '[]';

-- start_live_match_v2: accepts first server player
CREATE OR REPLACE FUNCTION start_live_match_v2(
  p_club_id        uuid,
  p_side_a         uuid[],
  p_side_b         uuid[],
  p_played_on      date,
  p_serving_player uuid
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id          uuid;
  v_serving_side text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  ) THEN
    RAISE EXCEPTION 'Not authorised';
  END IF;

  IF p_serving_player = ANY(p_side_a) THEN
    v_serving_side := 'A';
  ELSIF p_serving_player = ANY(p_side_b) THEN
    v_serving_side := 'B';
  ELSE
    RAISE EXCEPTION 'Serving player must be in side A or side B';
  END IF;

  INSERT INTO live_matches (
    club_id, side_a, side_b, played_on, status,
    score_a, score_b, serving_side, serving_player,
    current_game, games_a, games_b, game_scores,
    created_by
  ) VALUES (
    p_club_id, p_side_a, p_side_b, p_played_on, 'active',
    0, 0, v_serving_side, p_serving_player,
    1, 0, 0, '[]',
    auth.uid()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- add_live_point_v2: score by player ID
CREATE OR REPLACE FUNCTION add_live_point_v2(
  p_live_match_id    uuid,
  p_scored_by_player uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_match          live_matches%ROWTYPE;
  v_side           text;
  v_new_score_a    int;
  v_new_score_b    int;
  v_new_serving    text;
  v_new_server_pl  uuid;
  v_game_won       boolean := false;
  v_winner_side    text;
  v_new_games_a    int;
  v_new_games_b    int;
  v_new_game_num   int;
  v_new_game_scores jsonb;
BEGIN
  SELECT * INTO v_match FROM live_matches WHERE id = p_live_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'Match is not active'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_match.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  ) THEN
    RAISE EXCEPTION 'Not authorised';
  END IF;

  IF p_scored_by_player = ANY(v_match.side_a) THEN
    v_side := 'A';
  ELSIF p_scored_by_player = ANY(v_match.side_b) THEN
    v_side := 'B';
  ELSE
    RAISE EXCEPTION 'Player not in this match';
  END IF;

  v_new_score_a := v_match.score_a;
  v_new_score_b := v_match.score_b;

  IF v_side = 'A' THEN
    v_new_score_a := v_match.score_a + 1;
    -- Receiver scored → side A gets serve if they were receiving
    IF v_match.serving_side = 'B' THEN
      v_new_serving   := 'A';
      v_new_server_pl := v_match.side_a[1];
    ELSE
      v_new_serving   := v_match.serving_side;
      v_new_server_pl := v_match.serving_player;
    END IF;
  ELSE
    v_new_score_b := v_match.score_b + 1;
    IF v_match.serving_side = 'A' THEN
      v_new_serving   := 'B';
      v_new_server_pl := v_match.side_b[1];
    ELSE
      v_new_serving   := v_match.serving_side;
      v_new_server_pl := v_match.serving_player;
    END IF;
  END IF;

  -- Check game win: ≥21 with 2-point lead, or first to 30
  IF (v_new_score_a >= 21 AND v_new_score_a - v_new_score_b >= 2)
     OR (v_new_score_b >= 21 AND v_new_score_b - v_new_score_a >= 2)
     OR v_new_score_a = 30 OR v_new_score_b = 30
  THEN
    v_game_won := true;
    v_winner_side := CASE WHEN v_new_score_a > v_new_score_b THEN 'A' ELSE 'B' END;
  END IF;

  v_new_games_a    := v_match.games_a;
  v_new_games_b    := v_match.games_b;
  v_new_game_num   := v_match.current_game;
  v_new_game_scores := v_match.game_scores;

  IF v_game_won THEN
    v_new_game_scores := v_match.game_scores || jsonb_build_object('a', v_new_score_a, 'b', v_new_score_b);
    IF v_winner_side = 'A' THEN
      v_new_games_a := v_match.games_a + 1;
    ELSE
      v_new_games_b := v_match.games_b + 1;
    END IF;
    v_new_game_num := v_match.current_game + 1;
    -- Reset scores for next game
    v_new_score_a := 0;
    v_new_score_b := 0;
    -- Loser of game serves next
    v_new_serving   := CASE WHEN v_winner_side = 'A' THEN 'B' ELSE 'A' END;
    v_new_server_pl := CASE WHEN v_winner_side = 'A' THEN v_match.side_b[1] ELSE v_match.side_a[1] END;
  END IF;

  INSERT INTO live_match_points (
    live_match_id, game_number, scored_by, side,
    server_player, server_side,
    score_a_after, score_b_after
  ) VALUES (
    p_live_match_id, v_match.current_game, p_scored_by_player, v_side,
    v_match.serving_player, v_match.serving_side,
    v_new_score_a, v_new_score_b
  );

  UPDATE live_matches SET
    score_a        = v_new_score_a,
    score_b        = v_new_score_b,
    serving_side   = v_new_serving,
    serving_player = v_new_server_pl,
    current_game   = v_new_game_num,
    games_a        = v_new_games_a,
    games_b        = v_new_games_b,
    game_scores    = v_new_game_scores
  WHERE id = p_live_match_id;

  RETURN jsonb_build_object(
    'score_a',       v_new_score_a,
    'score_b',       v_new_score_b,
    'serving_side',  v_new_serving,
    'serving_player',v_new_server_pl,
    'current_game',  v_new_game_num,
    'game_scores',   v_new_game_scores,
    'games_a',       v_new_games_a,
    'games_b',       v_new_games_b,
    'game_won',      v_game_won,
    'winner_side',   v_winner_side,
    'side',          v_side
  );
END;
$$;

-- undo_live_point_v2
CREATE OR REPLACE FUNCTION undo_live_point_v2(
  p_live_match_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_match      live_matches%ROWTYPE;
  v_last       live_match_points%ROWTYPE;
  v_prev       live_match_points%ROWTYPE;
  v_restore_a  int;
  v_restore_b  int;
  v_restore_serving text;
  v_restore_server  uuid;
  v_restore_game    int;
  v_restore_scores  jsonb;
  v_restore_games_a int;
  v_restore_games_b int;
BEGIN
  SELECT * INTO v_match FROM live_matches WHERE id = p_live_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_match.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  ) THEN
    RAISE EXCEPTION 'Not authorised';
  END IF;

  SELECT * INTO v_last FROM live_match_points
  WHERE live_match_id = p_live_match_id
  ORDER BY created_at DESC LIMIT 1;

  IF NOT FOUND THEN RAISE EXCEPTION 'No points to undo'; END IF;

  SELECT * INTO v_prev FROM live_match_points
  WHERE live_match_id = p_live_match_id AND id <> v_last.id
  ORDER BY created_at DESC LIMIT 1;

  DELETE FROM live_match_points WHERE id = v_last.id;

  IF FOUND THEN
    v_restore_a       := v_prev.score_a_after;
    v_restore_b       := v_prev.score_b_after;
    v_restore_serving := v_prev.server_side;
    v_restore_server  := v_prev.server_player;
    v_restore_game    := v_prev.game_number;
  ELSE
    v_restore_a       := 0;
    v_restore_b       := 0;
    v_restore_serving := v_match.serving_side;
    v_restore_server  := v_match.serving_player;
    v_restore_game    := 1;
  END IF;

  -- If we're undoing a game-winning point, restore game state
  IF v_last.game_number < v_match.current_game THEN
    -- Undo the game win
    v_restore_game := v_last.game_number;
    v_restore_a    := v_last.score_a_after - CASE WHEN v_last.side = 'A' THEN 1 ELSE 0 END;
    v_restore_b    := v_last.score_b_after - CASE WHEN v_last.side = 'B' THEN 1 ELSE 0 END;
    v_restore_scores := (
      SELECT COALESCE(
        (SELECT jsonb_agg(elem) FROM jsonb_array_elements(v_match.game_scores) WITH ORDINALITY arr(elem, i)
         WHERE i < jsonb_array_length(v_match.game_scores)),
        '[]'::jsonb
      )
    );
    v_restore_games_a := v_match.games_a - CASE WHEN v_last.side = 'A' THEN 1 ELSE 0 END;
    v_restore_games_b := v_match.games_b - CASE WHEN v_last.side = 'B' THEN 1 ELSE 0 END;
  ELSE
    v_restore_scores  := v_match.game_scores;
    v_restore_games_a := v_match.games_a;
    v_restore_games_b := v_match.games_b;
    v_restore_a       := v_last.score_a_after - CASE WHEN v_last.side = 'A' THEN 1 ELSE 0 END;
    v_restore_b       := v_last.score_b_after - CASE WHEN v_last.side = 'B' THEN 1 ELSE 0 END;
    v_restore_serving := v_last.server_side;
    v_restore_server  := v_last.server_player;
  END IF;

  UPDATE live_matches SET
    score_a        = v_restore_a,
    score_b        = v_restore_b,
    serving_side   = v_restore_serving,
    serving_player = v_restore_server,
    current_game   = v_restore_game,
    games_a        = v_restore_games_a,
    games_b        = v_restore_games_b,
    game_scores    = v_restore_scores
  WHERE id = p_live_match_id;

  RETURN jsonb_build_object(
    'score_a',        v_restore_a,
    'score_b',        v_restore_b,
    'serving_side',   v_restore_serving,
    'serving_player', v_restore_server,
    'current_game',   v_restore_game,
    'game_scores',    v_restore_scores,
    'games_a',        v_restore_games_a,
    'games_b',        v_restore_games_b
  );
END;
$$;

GRANT EXECUTE ON FUNCTION start_live_match_v2(uuid, uuid[], uuid[], date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION add_live_point_v2(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION undo_live_point_v2(uuid) TO authenticated;
