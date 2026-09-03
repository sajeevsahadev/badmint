-- v104b_finalize_dedupe_user_placement
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

CREATE OR REPLACE FUNCTION public._finalize_tournament(p_tid uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_draw    text;
  v_first   uuid;
  v_second  uuid;
  v_third   uuid;
  v_final   record;
  v_bronze  uuid[];
BEGIN
  SELECT draw_type INTO v_draw FROM tournaments WHERE id = p_tid;

  IF v_draw = 'round_robin' THEN
    SELECT array_agg(registration_id ORDER BY wins DESC, (sets_for - sets_against) DESC, team_name)
      INTO v_bronze
      FROM v_tournament_standings WHERE tournament_id = p_tid;
    v_first  := v_bronze[1];
    v_second := v_bronze[2];
    v_third  := v_bronze[3];
    v_bronze := ARRAY[v_third];
  ELSE
    SELECT * INTO v_final
      FROM tournament_matches
     WHERE tournament_id = p_tid AND COALESCE(stage,'knockout') <> 'group'
       AND next_match_id IS NULL AND status = 'completed'
     ORDER BY round DESC LIMIT 1;
    IF FOUND THEN
      v_first  := v_final.winner_id;
      v_second := CASE WHEN v_final.winner_id = v_final.team_a_id
                       THEN v_final.team_b_id ELSE v_final.team_a_id END;
      SELECT array_agg(CASE WHEN winner_id = team_a_id THEN team_b_id ELSE team_a_id END
                       ORDER BY (score_a + score_b) DESC)
        INTO v_bronze
        FROM tournament_matches
       WHERE tournament_id = p_tid AND next_match_id = v_final.id AND status = 'completed';
      v_third := v_bronze[1];
    END IF;
  END IF;

  UPDATE tournaments
     SET status = 'completed',
         winner_registration_id    = v_first,
         runner_up_registration_id = v_second,
         third_registration_id     = v_third,
         updated_at = now()
   WHERE id = p_tid;

  DELETE FROM player_tournament_results WHERE tournament_id = p_tid;

  -- One row per user, keeping the best (lowest) placement, so the
  -- UNIQUE(user_id, tournament_id) constraint can never block a final result.
  INSERT INTO player_tournament_results (user_id, tournament_id, registration_id, placement)
  SELECT DISTINCT ON (uid) uid, p_tid, reg, place
  FROM (
    SELECT tr.player_a_user_id AS uid, tr.id AS reg, pl.place
      FROM (VALUES (v_first,1),(v_second,2)) AS pl(reg_id,place)
      JOIN tournament_registrations tr ON tr.id = pl.reg_id
     WHERE tr.player_a_user_id IS NOT NULL
    UNION ALL
    SELECT tr.player_b_user_id, tr.id, pl.place
      FROM (VALUES (v_first,1),(v_second,2)) AS pl(reg_id,place)
      JOIN tournament_registrations tr ON tr.id = pl.reg_id
     WHERE tr.player_b_user_id IS NOT NULL
    UNION ALL
    SELECT tr.player_a_user_id, tr.id, 3
      FROM tournament_registrations tr
     WHERE tr.id = ANY(v_bronze) AND tr.player_a_user_id IS NOT NULL
    UNION ALL
    SELECT tr.player_b_user_id, tr.id, 3
      FROM tournament_registrations tr
     WHERE tr.id = ANY(v_bronze) AND tr.player_b_user_id IS NOT NULL
  ) rows
  WHERE reg IS NOT NULL AND uid IS NOT NULL
  ORDER BY uid, place;
END;$$;;
