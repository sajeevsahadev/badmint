-- v103_save_generated_draw
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Save a client-computed draw (from utils/tournament-draw.js). Matches carry
-- client-generated ids + next-match linkage; we insert without the linkage first
-- (FK-safe), then set it in a second pass. Manager-gated.
CREATE OR REPLACE FUNCTION public.save_generated_draw(
  p_tournament_id uuid, p_matches jsonb, p_set_live boolean DEFAULT true
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF jsonb_typeof(p_matches) <> 'array' OR jsonb_array_length(p_matches) = 0 THEN
    RAISE EXCEPTION 'No matches to save'; END IF;

  DELETE FROM tournament_matches WHERE tournament_id = p_tournament_id;

  INSERT INTO tournament_matches
    (id, tournament_id, round, position, team_a_id, team_b_id, winner_id, status, stage, group_label, court)
  SELECT (x->>'id')::uuid, p_tournament_id, (x->>'round')::int, (x->>'position')::int,
         NULLIF(x->>'team_a_id','')::uuid, NULLIF(x->>'team_b_id','')::uuid, NULLIF(x->>'winner_id','')::uuid,
         COALESCE(x->>'status','pending'), COALESCE(x->>'stage','knockout'),
         NULLIF(x->>'group_label',''), NULLIF(x->>'court','')
  FROM jsonb_array_elements(p_matches) x;

  UPDATE tournament_matches tm
     SET next_match_id = (x->>'next_match_id')::uuid,
         next_match_slot = NULLIF(x->>'next_match_slot','')
  FROM jsonb_array_elements(p_matches) x
  WHERE tm.id = (x->>'id')::uuid
    AND x->>'next_match_id' IS NOT NULL AND x->>'next_match_id' <> '';

  IF p_set_live THEN
    UPDATE tournaments SET status='live', updated_at=now()
     WHERE id = p_tournament_id AND status <> 'completed';
  END IF;
END;$$;
GRANT EXECUTE ON FUNCTION public.save_generated_draw(uuid, jsonb, boolean) TO authenticated;;
