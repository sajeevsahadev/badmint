-- v93_update_match
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Edit a recorded match (players / scores / winner / date / name), then replay
-- the whole club's history to keep Elo + attendance consistent. Same replay
-- engine as delete_match. Authorized for the match creator or a club owner/manager.
CREATE OR REPLACE FUNCTION public.update_match(
  p_match_id     uuid,
  p_side_a       uuid[],
  p_side_b       uuid[],
  p_score_a      integer,
  p_score_b      integer,
  p_played_on    date DEFAULT NULL,
  p_display_name text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_club       uuid;
  v_created_by uuid;
  v_side_a_id  uuid;
  v_side_b_id  uuid;
  v_a_win      boolean;
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
  pid          uuid;
  v_old        numeric;
  v_new        numeric;
BEGIN
  SELECT club_id, created_by INTO v_club, v_created_by FROM matches WHERE id = p_match_id;
  IF v_club IS NULL THEN RAISE EXCEPTION 'Match not found'; END IF;

  -- Auth: match creator OR club owner/manager
  IF v_created_by IS DISTINCT FROM auth.uid() AND NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_club AND user_id = auth.uid() AND role IN ('owner','manager')
  ) THEN
    RAISE EXCEPTION 'Not authorized: only the match creator or a club owner/manager can edit matches';
  END IF;

  -- Validate the new line-up
  IF array_length(p_side_a, 1) <> 2 OR array_length(p_side_b, 1) <> 2 THEN
    RAISE EXCEPTION 'Each side must have exactly 2 players';
  END IF;
  IF (SELECT count(DISTINCT x) FROM unnest(p_side_a || p_side_b) AS x) <> 4 THEN
    RAISE EXCEPTION 'The four players must all be different';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(p_side_a || p_side_b) AS x
    WHERE x NOT IN (SELECT id FROM players WHERE club_id = v_club)
  ) THEN
    RAISE EXCEPTION 'All players must belong to this club';
  END IF;
  IF p_score_a = p_score_b THEN
    RAISE EXCEPTION 'Scores cannot be equal — a match needs a winner';
  END IF;

  v_a_win := p_score_a > p_score_b;

  -- Header (optional fields keep their current value when null)
  UPDATE matches SET
    played_on    = COALESCE(p_played_on, played_on),
    display_name = COALESCE(p_display_name, display_name)
  WHERE id = p_match_id;

  SELECT id INTO v_side_a_id FROM match_sides WHERE match_id = p_match_id AND side = 'A';
  SELECT id INTO v_side_b_id FROM match_sides WHERE match_id = p_match_id AND side = 'B';

  UPDATE match_sides SET score = p_score_a, is_winner = v_a_win     WHERE id = v_side_a_id;
  UPDATE match_sides SET score = p_score_b, is_winner = NOT v_a_win WHERE id = v_side_b_id;

  -- Replace participants (elo_before/after are recomputed by the replay)
  DELETE FROM match_participants WHERE match_side_id IN (v_side_a_id, v_side_b_id);
  FOREACH pid IN ARRAY p_side_a LOOP
    INSERT INTO match_participants(match_side_id, player_id, elo_before, elo_after) VALUES (v_side_a_id, pid, 0, 0);
  END LOOP;
  FOREACH pid IN ARRAY p_side_b LOOP
    INSERT INTO match_participants(match_side_id, player_id, elo_before, elo_after) VALUES (v_side_b_id, pid, 0, 0);
  END LOOP;

  -- ── Full replay in chronological order ──
  SELECT COALESCE(starting_elo, 1000), COALESCE(k_factor, 24)
  INTO v_start_elo, v_k FROM ranking_config WHERE club_id = v_club;

  UPDATE players SET elo = v_start_elo WHERE club_id = v_club;
  DELETE FROM attendance WHERE club_id = v_club;

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

    v_res_a := CASE WHEN m.score_a > m.score_b THEN 1 ELSE 0 END;
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
$function$;

GRANT EXECUTE ON FUNCTION public.update_match(uuid, uuid[], uuid[], integer, integer, date, text) TO authenticated;;
