-- v92_fix_generate_bracket_log
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Fix: log(2, n::float) → log(integer, double precision) has no match in PG.
-- log(base, x) requires numeric args. Cast both to numeric.
CREATE OR REPLACE FUNCTION public.generate_bracket(p_tournament_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_tour      record;
  v_teams     uuid[];
  n           int;
  n_rounds    int;
  padded      int;
  n_matches   int;
  a_slot      int;
  b_slot      int;
  team_a      uuid;
  team_b      uuid;
  is_bye_a    boolean;
  is_bye_b    boolean;
  r           int;
  i           int;
  prev_ids    uuid[];
  curr_ids    uuid[];
  new_id      uuid;
  pos         int;
BEGIN
  SELECT * INTO v_tour FROM tournaments WHERE id = p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;

  IF NOT (v_tour.created_by = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_tour.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  )) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT array_agg(id ORDER BY COALESCE(seed, 9999), created_at)
  INTO v_teams
  FROM tournament_registrations
  WHERE tournament_id = p_tournament_id AND status = 'confirmed';

  n := COALESCE(array_length(v_teams, 1), 0);
  IF n < 2 THEN RAISE EXCEPTION 'Need at least 2 confirmed teams to generate bracket'; END IF;

  DELETE FROM tournament_matches WHERE tournament_id = p_tournament_id;

  IF v_tour.format = 'single_elimination' THEN
    n_rounds  := GREATEST(1, ceil(log(2::numeric, n::numeric))::int);
    padded    := (2 ^ n_rounds)::int;
    n_matches := padded / 2;
    curr_ids  := '{}';

    FOR i IN 1..n_matches LOOP
      a_slot   := i;
      b_slot   := padded + 1 - i;
      is_bye_a := a_slot > n;
      is_bye_b := b_slot > n;
      team_a   := CASE WHEN NOT is_bye_a THEN v_teams[a_slot] ELSE NULL END;
      team_b   := CASE WHEN NOT is_bye_b THEN v_teams[b_slot] ELSE NULL END;

      INSERT INTO tournament_matches (
        tournament_id, round, position, team_a_id, team_b_id, status, winner_id
      ) VALUES (
        p_tournament_id, 1, i, team_a, team_b,
        CASE WHEN is_bye_a OR is_bye_b THEN 'bye' ELSE 'scheduled' END,
        CASE
          WHEN is_bye_b AND NOT is_bye_a THEN team_a
          WHEN is_bye_a AND NOT is_bye_b THEN team_b
          ELSE NULL
        END
      ) RETURNING id INTO new_id;
      curr_ids := array_append(curr_ids, new_id);
    END LOOP;

    FOR r IN 2..n_rounds LOOP
      prev_ids  := curr_ids;
      n_matches := n_matches / 2;
      curr_ids  := '{}';
      FOR i IN 1..n_matches LOOP
        INSERT INTO tournament_matches (tournament_id, round, position, status)
        VALUES (p_tournament_id, r, i, 'scheduled')
        RETURNING id INTO new_id;
        UPDATE tournament_matches SET next_match_id = new_id, next_match_slot = 'a'
        WHERE id = prev_ids[2*i - 1];
        UPDATE tournament_matches SET next_match_id = new_id, next_match_slot = 'b'
        WHERE id = prev_ids[2*i];
        curr_ids := array_append(curr_ids, new_id);
      END LOOP;
    END LOOP;

    FOR r IN 1..4 LOOP
      UPDATE tournament_matches nm
      SET team_a_id = CASE WHEN fm.next_match_slot = 'a' THEN fm.winner_id ELSE nm.team_a_id END,
          team_b_id = CASE WHEN fm.next_match_slot = 'b' THEN fm.winner_id ELSE nm.team_b_id END
      FROM tournament_matches fm
      WHERE fm.tournament_id = p_tournament_id
        AND fm.status = 'bye' AND fm.winner_id IS NOT NULL
        AND fm.next_match_id = nm.id AND nm.tournament_id = p_tournament_id;

      UPDATE tournament_matches
      SET status = 'bye', winner_id = COALESCE(team_a_id, team_b_id)
      WHERE tournament_id = p_tournament_id AND status = 'scheduled'
        AND ((team_a_id IS NULL) <> (team_b_id IS NULL));
    END LOOP;

  ELSIF v_tour.format = 'round_robin' THEN
    pos := 0;
    FOR i IN 1..n LOOP
      FOR r IN (i+1)..n LOOP
        pos := pos + 1;
        INSERT INTO tournament_matches (
          tournament_id, round, position, team_a_id, team_b_id, status
        ) VALUES (p_tournament_id, 1, pos, v_teams[i], v_teams[r], 'scheduled');
      END LOOP;
    END LOOP;

  ELSE
    RAISE EXCEPTION 'Unsupported format: %', v_tour.format;
  END IF;

  UPDATE tournaments SET status = 'live', updated_at = now()
  WHERE id = p_tournament_id;
END;
$function$;;
