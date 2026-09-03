-- v104_tournament_live_scoring
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- ═══════════════════════════════════════════════════════════════════════
-- v104: Tournament Phase 3 — robust live scoring, standings-aware completion,
-- podium placements → player profiles, and knockout-from-groups append.
--
-- Fixes real bugs in the old record_tournament_result:
--   • next_match_slot compared to lowercase 'a' but the draw engine emits 'A'/'B'
--     → winners always advanced into the wrong slot.
--   • completion detected via status='scheduled' while the engine emits
--     'pending'/'scheduled' → round-robin completed after the first result.
--   • winner_registration_id keyed off the legacy `format` column, not draw_type.
-- ═══════════════════════════════════════════════════════════════════════

-- ── Compute + persist final placements when a tournament finishes ──
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
    -- Rank by wins, then set difference. Group-stage matches don't exist here.
    SELECT array_agg(registration_id ORDER BY wins DESC, (sets_for - sets_against) DESC, team_name)
      INTO v_bronze
      FROM v_tournament_standings WHERE tournament_id = p_tid;
    v_first  := v_bronze[1];
    v_second := v_bronze[2];
    v_third  := v_bronze[3];
  ELSE
    -- knockout / groups_knockout: the final is the non-group match that feeds
    -- nothing. Winner = 1st, other finalist = 2nd, the two semifinal losers
    -- share bronze (badminton convention).
    SELECT * INTO v_final
      FROM tournament_matches
     WHERE tournament_id = p_tid AND COALESCE(stage,'knockout') <> 'group'
       AND next_match_id IS NULL AND status = 'completed'
     ORDER BY round DESC LIMIT 1;
    IF FOUND THEN
      v_first  := v_final.winner_id;
      v_second := CASE WHEN v_final.winner_id = v_final.team_a_id
                       THEN v_final.team_b_id ELSE v_final.team_a_id END;
      -- semifinal losers (matches feeding the final)
      SELECT array_agg(CASE WHEN winner_id = team_a_id THEN team_b_id ELSE team_a_id END
                       ORDER BY (score_a + score_b) DESC)
        INTO v_bronze
        FROM tournament_matches
       WHERE tournament_id = p_tid AND next_match_id = v_final.id AND status = 'completed';
      v_third := v_bronze[1];   -- displayed bronze; both semifinal losers recorded below
    END IF;
  END IF;

  UPDATE tournaments
     SET status = 'completed',
         winner_registration_id    = v_first,
         runner_up_registration_id = v_second,
         third_registration_id     = v_third,
         updated_at = now()
   WHERE id = p_tid;

  -- Rebuild player placement rows (idempotent).
  DELETE FROM player_tournament_results WHERE tournament_id = p_tid;

  INSERT INTO player_tournament_results (user_id, tournament_id, registration_id, placement)
  SELECT uid, p_tid, reg, place FROM (
    SELECT tr.player_a_user_id AS uid, tr.id AS reg, pl.place
      FROM (VALUES (v_first,1),(v_second,2)) AS pl(reg_id,place)
      JOIN tournament_registrations tr ON tr.id = pl.reg_id
     WHERE tr.player_a_user_id IS NOT NULL
    UNION ALL
    SELECT tr.player_b_user_id, tr.id, pl.place
      FROM (VALUES (v_first,1),(v_second,2)) AS pl(reg_id,place)
      JOIN tournament_registrations tr ON tr.id = pl.reg_id
     WHERE tr.player_b_user_id IS NOT NULL
    -- bronze: every semifinal loser (or 3rd-ranked round robin team) at placement 3
    UNION ALL
    SELECT tr.player_a_user_id, tr.id, 3
      FROM tournament_registrations tr
     WHERE tr.id = ANY(CASE WHEN v_draw = 'round_robin' THEN ARRAY[v_third] ELSE v_bronze END)
       AND tr.player_a_user_id IS NOT NULL
    UNION ALL
    SELECT tr.player_b_user_id, tr.id, 3
      FROM tournament_registrations tr
     WHERE tr.id = ANY(CASE WHEN v_draw = 'round_robin' THEN ARRAY[v_third] ELSE v_bronze END)
       AND tr.player_b_user_id IS NOT NULL
  ) rows
  WHERE reg IS NOT NULL AND uid IS NOT NULL;
END;$$;

-- ── Record a match result (live scoring) ──
CREATE OR REPLACE FUNCTION public.record_tournament_result(p_match_id uuid, p_score_a integer, p_score_b integer)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_match     record;
  v_winner_id uuid;
  v_slot      text;
  v_remaining int;
  v_ko_exists boolean;
  v_next      record;
BEGIN
  SELECT tm.*, t.club_id, t.created_by AS tour_creator, t.draw_type AS draw_type
    INTO v_match
    FROM tournament_matches tm
    JOIN tournaments t ON t.id = tm.tournament_id
   WHERE tm.id = p_match_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF v_match.status = 'completed' THEN RAISE EXCEPTION 'Match already completed'; END IF;
  IF v_match.status = 'bye'       THEN RAISE EXCEPTION 'Cannot record result for a BYE'; END IF;
  IF v_match.team_a_id IS NULL OR v_match.team_b_id IS NULL THEN
    RAISE EXCEPTION 'Both teams must be set before recording a result';
  END IF;
  IF NOT (v_match.tour_creator = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members
     WHERE club_id = v_match.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  )) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_score_a = p_score_b THEN
    RAISE EXCEPTION 'Scores cannot be equal — there must be a winner';
  END IF;

  v_winner_id := CASE WHEN p_score_a > p_score_b THEN v_match.team_a_id ELSE v_match.team_b_id END;

  UPDATE tournament_matches
     SET score_a = p_score_a, score_b = p_score_b, winner_id = v_winner_id, status = 'completed'
   WHERE id = p_match_id;

  -- Advance winner into the next match (case-insensitive slot), then flip that
  -- match to 'scheduled' once both of its teams are known.
  IF v_match.next_match_id IS NOT NULL THEN
    v_slot := lower(COALESCE(v_match.next_match_slot,'a'));
    IF v_slot = 'a' THEN
      UPDATE tournament_matches SET team_a_id = v_winner_id WHERE id = v_match.next_match_id;
    ELSE
      UPDATE tournament_matches SET team_b_id = v_winner_id WHERE id = v_match.next_match_id;
    END IF;
    SELECT * INTO v_next FROM tournament_matches WHERE id = v_match.next_match_id;
    IF v_next.team_a_id IS NOT NULL AND v_next.team_b_id IS NOT NULL AND v_next.status = 'pending' THEN
      UPDATE tournament_matches SET status = 'scheduled' WHERE id = v_next.id;
    END IF;
  END IF;

  -- Completion: no more playable matches remain.
  SELECT count(*) INTO v_remaining
    FROM tournament_matches
   WHERE tournament_id = v_match.tournament_id AND status IN ('pending','scheduled');

  IF v_remaining = 0 THEN
    -- For groups_knockout, finishing only the group stage is NOT the end —
    -- the director still has to generate the knockout.
    SELECT EXISTS (
      SELECT 1 FROM tournament_matches
       WHERE tournament_id = v_match.tournament_id AND COALESCE(stage,'knockout') <> 'group'
    ) INTO v_ko_exists;

    IF v_match.draw_type <> 'groups_knockout' OR v_ko_exists THEN
      PERFORM _finalize_tournament(v_match.tournament_id);
    END IF;
  END IF;
END;$$;

-- ── Append the knockout stage built from group standings (groups_knockout) ──
-- Insert-only: leaves the completed group matches intact.
CREATE OR REPLACE FUNCTION public.save_knockout_stage(p_tournament_id uuid, p_matches jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF jsonb_typeof(p_matches) <> 'array' OR jsonb_array_length(p_matches) = 0 THEN
    RAISE EXCEPTION 'No knockout matches to save'; END IF;
  IF EXISTS (SELECT 1 FROM tournament_matches
             WHERE tournament_id = p_tournament_id AND COALESCE(stage,'knockout') <> 'group') THEN
    RAISE EXCEPTION 'Knockout stage already generated';
  END IF;

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
END;$$;

GRANT EXECUTE ON FUNCTION public.record_tournament_result(uuid,integer,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_knockout_stage(uuid,jsonb) TO authenticated;
;
