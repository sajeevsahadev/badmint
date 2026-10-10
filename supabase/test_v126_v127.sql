-- =====================================================================
-- E2E test cases for v126 (PaySplits settle-up) + v127 (soft-delete clubs).
-- Run in Supabase SQL Editor. Each block seeds isolated data, asserts with
-- RAISE EXCEPTION on failure, and cleans up. "no rows / NOTICE PASSED" = pass.
-- =====================================================================

-- ── v126: PaySplits settle-up (8 cases) ──────────────────────────────
DO $$
DECLARE
  v_user uuid; v_club uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid(); v_b uuid := gen_random_uuid(); v_c uuid := gen_random_uuid();
  v_net numeric; v_rows int; v_raised boolean;
BEGIN
  SELECT id INTO v_user FROM auth.users LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user::text)::text, true);
  INSERT INTO clubs(id, name, created_by) VALUES (v_club, 'E2E Settle Test', v_user);
  INSERT INTO club_members(club_id, user_id, role) VALUES (v_club, v_user, 'owner');
  INSERT INTO players(id, club_id, display_name) VALUES (v_a,v_club,'A'),(v_b,v_club,'B'),(v_c,v_club,'C');
  -- A pays 30 split A,B,C => B owes A 10, C owes A 10
  PERFORM add_expense(v_club,'Court','court',30,v_a,CURRENT_DATE,ARRAY[v_a,v_b,v_c],NULL,false,NULL);
  SELECT net_amount INTO v_net FROM get_balance_summary(v_club) WHERE from_player_id=v_b AND to_player_id=v_a;
  IF v_net IS DISTINCT FROM 10 THEN RAISE EXCEPTION 'T1 FAIL B->A %', v_net; END IF;          -- T1 expense debt
  PERFORM add_settlement(v_club, v_b, v_a, 10, 'cash');                                        -- T2 full settle clears
  PERFORM 1 FROM get_balance_summary(v_club) WHERE from_player_id=v_b AND to_player_id=v_a;
  IF FOUND THEN RAISE EXCEPTION 'T2 FAIL B->A not cleared'; END IF;
  SELECT net_amount INTO v_net FROM get_balance_summary(v_club) WHERE from_player_id=v_c AND to_player_id=v_a;
  IF v_net IS DISTINCT FROM 10 THEN RAISE EXCEPTION 'T3 FAIL C->A changed %', v_net; END IF;   -- T3 others unaffected
  PERFORM add_settlement(v_club, v_c, v_a, 4, NULL);                                            -- T4 partial settle
  SELECT net_amount INTO v_net FROM get_balance_summary(v_club) WHERE from_player_id=v_c AND to_player_id=v_a;
  IF v_net IS DISTINCT FROM 6 THEN RAISE EXCEPTION 'T4 FAIL C->A %', v_net; END IF;
  PERFORM add_settlement(v_club, v_b, v_a, 15, NULL);                                           -- T5 overpay reverses
  SELECT net_amount INTO v_net FROM get_balance_summary(v_club) WHERE from_player_id=v_a AND to_player_id=v_b;
  IF v_net IS DISTINCT FROM 15 THEN RAISE EXCEPTION 'T5 FAIL A->B %', v_net; END IF;
  SELECT count(*) INTO v_rows FROM get_settlements(v_club);
  IF v_rows <> 3 THEN RAISE EXCEPTION 'T6 FAIL settlements %', v_rows; END IF;                  -- T6 history
  v_raised := false; BEGIN PERFORM add_settlement(v_club, v_a, v_a, 5, NULL); EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  IF NOT v_raised THEN RAISE EXCEPTION 'T7 FAIL same-player allowed'; END IF;                   -- T7 validation
  v_raised := false; BEGIN PERFORM add_settlement(v_club, v_b, v_a, -5, NULL); EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  IF NOT v_raised THEN RAISE EXCEPTION 'T8 FAIL negative allowed'; END IF;                      -- T8 validation
  RAISE NOTICE 'v126 SETTLE-UP: ALL 8 PASSED';
  DELETE FROM clubs WHERE id = v_club;
END $$;

-- ── v127: soft-delete clubs (11 cases) ───────────────────────────────
DO $$
DECLARE v_admin uuid; v_club uuid := gen_random_uuid(); v_raised boolean;
BEGIN
  SELECT ar.user_id INTO v_admin FROM app_roles ar WHERE ar.role='app_admin' LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  INSERT INTO clubs(id,name,created_by,is_public,join_policy) VALUES (v_club,'E2E SoftDel',v_admin,true,'open');
  INSERT INTO club_members(club_id,user_id,role) VALUES (v_club,v_admin,'owner');
  IF NOT EXISTS (SELECT 1 FROM admin_get_clubs() WHERE club_id=v_club) THEN RAISE EXCEPTION 'S1'; END IF;
  IF EXISTS (SELECT 1 FROM admin_get_deleted_clubs() WHERE club_id=v_club) THEN RAISE EXCEPTION 'S2'; END IF;
  PERFORM admin_delete_club(v_club);
  IF (SELECT deleted_at FROM clubs WHERE id=v_club) IS NULL THEN RAISE EXCEPTION 'S3'; END IF;
  IF EXISTS (SELECT 1 FROM admin_get_clubs() WHERE club_id=v_club) THEN RAISE EXCEPTION 'S4'; END IF;
  IF NOT EXISTS (SELECT 1 FROM admin_get_deleted_clubs() WHERE club_id=v_club) THEN RAISE EXCEPTION 'S5'; END IF;
  IF EXISTS (SELECT 1 FROM get_public_clubs() WHERE id=v_club) THEN RAISE EXCEPTION 'S6'; END IF;
  IF EXISTS (SELECT 1 FROM get_club_ranking(v_club)) THEN RAISE EXCEPTION 'S7'; END IF;
  v_raised := false; BEGIN PERFORM admin_delete_club(v_club); EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  IF NOT v_raised THEN RAISE EXCEPTION 'S8 double-delete allowed'; END IF;
  PERFORM admin_restore_club(v_club);
  IF (SELECT deleted_at FROM clubs WHERE id=v_club) IS NOT NULL THEN RAISE EXCEPTION 'S9'; END IF;
  IF NOT EXISTS (SELECT 1 FROM admin_get_clubs() WHERE club_id=v_club) THEN RAISE EXCEPTION 'S10'; END IF;
  PERFORM admin_purge_club(v_club);
  IF EXISTS (SELECT 1 FROM clubs WHERE id=v_club) THEN RAISE EXCEPTION 'S11'; END IF;
  RAISE NOTICE 'v127 SOFT-DELETE: ALL 11 PASSED';
END $$;
