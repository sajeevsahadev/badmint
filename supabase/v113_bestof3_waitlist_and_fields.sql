-- v113_bestof3_waitlist_and_fields
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- ═══════════════════════════════════════════════════════════════════════
-- v113: tournament enhancements — best-of-3 scoring (flagged, per tournament),
-- waitlist when full, and new metadata columns (category, skill level,
-- per-tournament currency).
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS best_of_3   boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS category    text,
  ADD COLUMN IF NOT EXISTS skill_level text,
  ADD COLUMN IF NOT EXISTS currency    text;
ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS games jsonb;   -- [{a,b},…] per-game scores when best_of_3

-- ── Shared core: apply a decided result, advance the bracket, finalize ──
-- score_a/score_b are POINTS (single) or GAMES WON (best-of-3). p_games is the
-- per-game breakdown for best-of-3 (null for single).
CREATE OR REPLACE FUNCTION public._apply_match_result(
  p_match_id uuid, p_score_a integer, p_score_b integer, p_games jsonb DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_match record; v_winner_id uuid; v_slot text; v_remaining int;
  v_ko_exists boolean; v_next record;
BEGIN
  SELECT tm.*, t.club_id, t.created_by AS tour_creator, t.draw_type AS draw_type
    INTO v_match
    FROM tournament_matches tm JOIN tournaments t ON t.id = tm.tournament_id
   WHERE tm.id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF v_match.status = 'completed' THEN RAISE EXCEPTION 'Match already completed'; END IF;
  IF v_match.status = 'bye'       THEN RAISE EXCEPTION 'Cannot record result for a BYE'; END IF;
  IF v_match.team_a_id IS NULL OR v_match.team_b_id IS NULL THEN
    RAISE EXCEPTION 'Both teams must be set before recording a result'; END IF;
  IF NOT (v_match.tour_creator = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members WHERE club_id = v_match.club_id AND user_id = auth.uid()
       AND role IN ('owner','manager'))) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_score_a = p_score_b THEN RAISE EXCEPTION 'There must be a winner'; END IF;

  v_winner_id := CASE WHEN p_score_a > p_score_b THEN v_match.team_a_id ELSE v_match.team_b_id END;

  UPDATE tournament_matches
     SET score_a = p_score_a, score_b = p_score_b, games = p_games,
         winner_id = v_winner_id, status = 'completed'
   WHERE id = p_match_id;

  IF v_match.next_match_id IS NOT NULL THEN
    v_slot := lower(COALESCE(v_match.next_match_slot,'a'));
    IF v_slot = 'a' THEN UPDATE tournament_matches SET team_a_id = v_winner_id WHERE id = v_match.next_match_id;
    ELSE                 UPDATE tournament_matches SET team_b_id = v_winner_id WHERE id = v_match.next_match_id; END IF;
    SELECT * INTO v_next FROM tournament_matches WHERE id = v_match.next_match_id;
    IF v_next.team_a_id IS NOT NULL AND v_next.team_b_id IS NOT NULL AND v_next.status = 'pending' THEN
      UPDATE tournament_matches SET status = 'scheduled' WHERE id = v_next.id; END IF;
  END IF;

  SELECT count(*) INTO v_remaining FROM tournament_matches
   WHERE tournament_id = v_match.tournament_id AND status IN ('pending','scheduled');
  IF v_remaining = 0 THEN
    SELECT EXISTS (SELECT 1 FROM tournament_matches
       WHERE tournament_id = v_match.tournament_id AND COALESCE(stage,'knockout') <> 'group') INTO v_ko_exists;
    IF v_match.draw_type <> 'groups_knockout' OR v_ko_exists THEN
      PERFORM _finalize_tournament(v_match.tournament_id);
    END IF;
  END IF;
END;$$;
REVOKE EXECUTE ON FUNCTION public._apply_match_result(uuid,integer,integer,jsonb) FROM public, anon, authenticated;

-- Single-score result (unchanged interface) now delegates to the shared core.
CREATE OR REPLACE FUNCTION public.record_tournament_result(p_match_id uuid, p_score_a integer, p_score_b integer)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF p_score_a = p_score_b THEN RAISE EXCEPTION 'Scores cannot be equal — there must be a winner'; END IF;
  PERFORM _apply_match_result(p_match_id, p_score_a, p_score_b, NULL);
END;$$;
GRANT EXECUTE ON FUNCTION public.record_tournament_result(uuid,integer,integer) TO authenticated;

-- Best-of-3 result: validate the games array, derive games won, then apply.
CREATE OR REPLACE FUNCTION public.record_tournament_games(p_match_id uuid, p_games jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE g jsonb; a int; b int; won_a int := 0; won_b int := 0; n int; prev_winner text; cur_winner text;
BEGIN
  IF jsonb_typeof(p_games) <> 'array' THEN RAISE EXCEPTION 'Games must be an array'; END IF;
  n := jsonb_array_length(p_games);
  IF n < 2 OR n > 3 THEN RAISE EXCEPTION 'Best of 3 must have 2 or 3 games'; END IF;
  prev_winner := NULL;
  FOR g IN SELECT * FROM jsonb_array_elements(p_games) LOOP
    a := (g->>'a')::int; b := (g->>'b')::int;
    IF a IS NULL OR b IS NULL OR a < 0 OR b < 0 THEN RAISE EXCEPTION 'Invalid game score'; END IF;
    IF a = b THEN RAISE EXCEPTION 'Each game must have a winner'; END IF;
    cur_winner := CASE WHEN a > b THEN 'a' ELSE 'b' END;
    IF cur_winner = 'a' THEN won_a := won_a + 1; ELSE won_b := won_b + 1; END IF;
    prev_winner := cur_winner;
  END LOOP;
  -- Best of 3: the match ends when a side reaches 2; a 3rd game only exists if 1-1.
  IF GREATEST(won_a, won_b) <> 2 THEN RAISE EXCEPTION 'One team must win 2 games'; END IF;
  IF n = 3 AND (won_a <> 2 OR won_b <> 1) AND (won_b <> 2 OR won_a <> 1) THEN
    RAISE EXCEPTION 'Invalid best-of-3 sequence'; END IF;
  PERFORM _apply_match_result(p_match_id, won_a, won_b, p_games);
END;$$;
GRANT EXECUTE ON FUNCTION public.record_tournament_games(uuid,jsonb) TO authenticated;

-- ── Waitlist: register when full (status 'waitlisted' instead of rejecting) ──
CREATE OR REPLACE FUNCTION public.register_for_tournament(
  p_tournament_id uuid, p_team_name text, p_player_a_name text,
  p_player_b_name text DEFAULT NULL, p_notes text DEFAULT NULL, p_contact_phone text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_tour record; v_count int; v_id uuid; v_status text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required to register'; END IF;
  SELECT * INTO v_tour FROM tournaments WHERE id=p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF v_tour.status <> 'registration_open' THEN RAISE EXCEPTION 'Registration is not open for this tournament'; END IF;
  IF EXISTS (SELECT 1 FROM tournament_registrations
             WHERE tournament_id=p_tournament_id AND registered_by=auth.uid()
               AND status NOT IN ('rejected','withdrawn'))
  THEN RAISE EXCEPTION 'You have already registered a team for this tournament'; END IF;
  -- Capacity is counted from confirmed + pending; when full, new teams go on the waitlist.
  SELECT COUNT(*) INTO v_count FROM tournament_registrations
   WHERE tournament_id=p_tournament_id AND status IN ('pending','confirmed');
  v_status := CASE WHEN v_count >= v_tour.max_teams THEN 'waitlisted' ELSE 'pending' END;
  INSERT INTO tournament_registrations
    (tournament_id,team_name,player_a_name,player_b_name,registered_by,notes,contact_phone,player_a_user_id,status,payment_status)
  VALUES (p_tournament_id,trim(p_team_name),trim(p_player_a_name),NULLIF(trim(p_player_b_name),''),
          auth.uid(),p_notes,p_contact_phone,auth.uid(),v_status,'pending')
  RETURNING id INTO v_id;
  RETURN v_id;
END;$$;

-- Approving must respect capacity (a confirmed team must withdraw to free a spot).
CREATE OR REPLACE FUNCTION public.approve_registration(p_reg_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_tid uuid; v_max int; v_confirmed int;
BEGIN
  SELECT tournament_id INTO v_tid FROM tournament_registrations WHERE id = p_reg_id;
  IF v_tid IS NULL THEN RAISE EXCEPTION 'Registration not found'; END IF;
  IF NOT _can_manage_tournament(v_tid) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT max_teams INTO v_max FROM tournaments WHERE id = v_tid;
  SELECT COUNT(*) INTO v_confirmed FROM tournament_registrations
   WHERE tournament_id = v_tid AND status = 'confirmed';
  IF v_confirmed >= v_max THEN
    RAISE EXCEPTION 'Tournament is full (% teams) — a confirmed team must withdraw first', v_max;
  END IF;
  UPDATE tournament_registrations SET status = 'confirmed', payment_status = 'confirmed' WHERE id = p_reg_id;
END;$$;;
