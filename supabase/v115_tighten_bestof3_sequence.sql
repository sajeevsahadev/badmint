-- v115_tighten_bestof3_sequence
-- Reject a best-of-3 games array where a 3rd game is recorded after the match
-- was already decided 2-0 (winner is still correct, but the sequence is
-- impossible — catches director input errors).
CREATE OR REPLACE FUNCTION public.record_tournament_games(p_match_id uuid, p_games jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE g jsonb; a int; b int; won_a int := 0; won_b int := 0; n int; idx int := 0;
BEGIN
  IF jsonb_typeof(p_games) <> 'array' THEN RAISE EXCEPTION 'Games must be an array'; END IF;
  n := jsonb_array_length(p_games);
  IF n < 2 OR n > 3 THEN RAISE EXCEPTION 'Best of 3 must have 2 or 3 games'; END IF;
  FOR g IN SELECT * FROM jsonb_array_elements(p_games) LOOP
    a := (g->>'a')::int; b := (g->>'b')::int;
    IF a IS NULL OR b IS NULL OR a < 0 OR b < 0 THEN RAISE EXCEPTION 'Invalid game score'; END IF;
    IF a = b THEN RAISE EXCEPTION 'Each game must have a winner'; END IF;
    IF GREATEST(won_a, won_b) = 2 THEN RAISE EXCEPTION 'Match was already decided before game %', idx + 1; END IF;
    IF a > b THEN won_a := won_a + 1; ELSE won_b := won_b + 1; END IF;
    idx := idx + 1;
  END LOOP;
  IF GREATEST(won_a, won_b) <> 2 THEN RAISE EXCEPTION 'One team must win 2 games'; END IF;
  PERFORM _apply_match_result(p_match_id, won_a, won_b, p_games);
END;$$;
