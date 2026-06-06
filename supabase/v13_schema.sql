-- =====================================================================
-- Badmint v13 — Open match recording to all members; delete = creator or owner
-- Run in Supabase SQL Editor after v12_schema.sql
-- =====================================================================

-- ── record_match: any club member may now record a match ──────────────
DROP FUNCTION IF EXISTS record_match(uuid, date, uuid[], uuid[], integer, integer, text);
CREATE OR REPLACE FUNCTION record_match(
  p_club_id      uuid,
  p_played_on    date,
  p_side_a       uuid[],
  p_side_b       uuid[],
  p_score_a      integer,
  p_score_b      integer,
  p_display_name text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_match_id  uuid;
  v_side_a_id uuid;
  v_side_b_id uuid;
  v_k         integer;
  v_a_avg     numeric;
  v_b_avg     numeric;
  v_exp_a     numeric;
  v_exp_b     numeric;
  v_res_a     numeric;
  v_res_b     numeric;
  v_a_win     boolean;
  pid         uuid;
  v_old       numeric;
  v_new       numeric;
BEGIN
  -- Any club member may record a match (owner, manager, or player)
  IF NOT EXISTS (
    SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()
  ) THEN RAISE EXCEPTION 'Not a member of this club'; END IF;

  IF array_length(p_side_a, 1) <> 2 OR array_length(p_side_b, 1) <> 2 THEN
    RAISE EXCEPTION 'Each side must have exactly 2 players';
  END IF;

  SELECT COALESCE(k_factor, 24) INTO v_k FROM ranking_config WHERE club_id = p_club_id;
  IF v_k IS NULL THEN v_k := 24; END IF;

  v_a_win := p_score_a > p_score_b;
  v_res_a := CASE WHEN v_a_win THEN 1 ELSE 0 END;
  v_res_b := 1 - v_res_a;

  SELECT avg(elo) INTO v_a_avg FROM players WHERE id = ANY(p_side_a);
  SELECT avg(elo) INTO v_b_avg FROM players WHERE id = ANY(p_side_b);
  v_exp_a := 1.0 / (1.0 + power(10, (v_b_avg - v_a_avg) / 400.0));
  v_exp_b := 1.0 / (1.0 + power(10, (v_a_avg - v_b_avg) / 400.0));

  INSERT INTO matches(club_id, played_on, created_by, display_name)
    VALUES (p_club_id, COALESCE(p_played_on, current_date), auth.uid(), p_display_name)
    RETURNING id INTO v_match_id;

  INSERT INTO match_sides(match_id, side, score, is_winner)
    VALUES (v_match_id, 'A', p_score_a,  v_a_win)     RETURNING id INTO v_side_a_id;
  INSERT INTO match_sides(match_id, side, score, is_winner)
    VALUES (v_match_id, 'B', p_score_b, NOT v_a_win)  RETURNING id INTO v_side_b_id;

  FOREACH pid IN ARRAY p_side_a LOOP
    SELECT elo INTO v_old FROM players WHERE id = pid;
    v_new := v_old + v_k * (v_res_a - v_exp_a);
    UPDATE players SET elo = v_new WHERE id = pid;
    INSERT INTO match_participants(match_side_id, player_id, elo_before, elo_after)
      VALUES (v_side_a_id, pid, v_old, v_new);
  END LOOP;

  FOREACH pid IN ARRAY p_side_b LOOP
    SELECT elo INTO v_old FROM players WHERE id = pid;
    v_new := v_old + v_k * (v_res_b - v_exp_b);
    UPDATE players SET elo = v_new WHERE id = pid;
    INSERT INTO match_participants(match_side_id, player_id, elo_before, elo_after)
      VALUES (v_side_b_id, pid, v_old, v_new);
  END LOOP;

  INSERT INTO attendance(club_id, player_id, played_on)
  SELECT p_club_id, x, COALESCE(p_played_on, current_date)
  FROM unnest(p_side_a || p_side_b) AS x
  ON CONFLICT (player_id, played_on) DO NOTHING;

  RETURN v_match_id;
END;
$$;

GRANT EXECUTE ON FUNCTION record_match(uuid, date, uuid[], uuid[], integer, integer, text) TO authenticated;

-- ── delete_match: only the match creator OR the club owner may delete ──
CREATE OR REPLACE FUNCTION delete_match(p_match_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_club       uuid;
  v_created_by uuid;
  v_start_elo  integer;
  v_k          integer;
  m            record;
  v_a_players  uuid[];
  v_b_players  uuid[];
  v_a_avg      numeric;
  v_b_avg      numeric;
  v_exp_a      numeric;
  v_exp_b      numeric;
  v_res_a      numeric;
  v_res_b      numeric;
  v_a_win      boolean;
  pid          uuid;
  v_old        numeric;
  v_new        numeric;
BEGIN
  SELECT club_id, created_by INTO v_club, v_created_by
  FROM matches WHERE id = p_match_id;
  IF v_club IS NULL THEN RAISE EXCEPTION 'Match not found'; END IF;

  -- Allow: match creator OR club owner
  IF v_created_by IS DISTINCT FROM auth.uid() AND NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_club AND user_id = auth.uid() AND role = 'owner'
  ) THEN
    RAISE EXCEPTION 'Not authorized: only the match creator or club owner can delete matches';
  END IF;

  SELECT COALESCE(starting_elo, 1000), COALESCE(k_factor, 24)
  INTO v_start_elo, v_k
  FROM ranking_config WHERE club_id = v_club;

  -- 1. Delete target match (cascades)
  DELETE FROM matches WHERE id = p_match_id;

  -- 2. Reset all club players to starting Elo
  UPDATE players SET elo = v_start_elo WHERE club_id = v_club;

  -- 3. Rebuild attendance from scratch
  DELETE FROM attendance WHERE club_id = v_club;

  -- 4. Replay remaining matches in chronological order
  FOR m IN
    SELECT ma.played_on,
           sa.id AS side_a_id, sb.id AS side_b_id,
           sa.score AS score_a, sb.score AS score_b
    FROM matches ma
    JOIN match_sides sa ON sa.match_id = ma.id AND sa.side = 'A'
    JOIN match_sides sb ON sb.match_id = ma.id AND sb.side = 'B'
    WHERE ma.club_id = v_club
    ORDER BY ma.played_on, ma.created_at
  LOOP
    SELECT array_agg(player_id) INTO v_a_players FROM match_participants WHERE match_side_id = m.side_a_id;
    SELECT array_agg(player_id) INTO v_b_players FROM match_participants WHERE match_side_id = m.side_b_id;

    v_a_win := m.score_a > m.score_b;
    v_res_a := CASE WHEN v_a_win THEN 1 ELSE 0 END;
    v_res_b := 1 - v_res_a;

    SELECT avg(elo) INTO v_a_avg FROM players WHERE id = ANY(v_a_players);
    SELECT avg(elo) INTO v_b_avg FROM players WHERE id = ANY(v_b_players);
    v_exp_a := 1.0 / (1.0 + power(10, (v_b_avg - v_a_avg) / 400.0));
    v_exp_b := 1.0 / (1.0 + power(10, (v_a_avg - v_b_avg) / 400.0));

    FOREACH pid IN ARRAY v_a_players LOOP
      SELECT elo INTO v_old FROM players WHERE id = pid;
      v_new := v_old + v_k * (v_res_a - v_exp_a);
      UPDATE players SET elo = v_new WHERE id = pid;
      UPDATE match_participants SET elo_before = v_old, elo_after = v_new
        WHERE match_side_id = m.side_a_id AND player_id = pid;
    END LOOP;

    FOREACH pid IN ARRAY v_b_players LOOP
      SELECT elo INTO v_old FROM players WHERE id = pid;
      v_new := v_old + v_k * (v_res_b - v_exp_b);
      UPDATE players SET elo = v_new WHERE id = pid;
      UPDATE match_participants SET elo_before = v_old, elo_after = v_new
        WHERE match_side_id = m.side_b_id AND player_id = pid;
    END LOOP;

    INSERT INTO attendance(club_id, player_id, played_on)
    SELECT v_club, unnest(v_a_players || v_b_players), m.played_on
    ON CONFLICT (player_id, played_on) DO NOTHING;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_match(uuid) TO authenticated;
