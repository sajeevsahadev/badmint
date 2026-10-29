-- =====================================================================
-- Badminton 360 v140 — Fix merge_players de-dupe (session_rotations, share_links)
-- Applied to prod via Supabase MCP; archived for rebuild parity.
--
-- BUG: merge_players reassigned player_id with a plain UPDATE on two tables that
-- carry a UNIQUE constraint involving player_id:
--   * session_rotations  UNIQUE (club_id, session_date, player_id)
--   * share_links        UNIQUE (player_id)
-- When BOTH players had a row in the same session, or both had a share link, the
-- UPDATE raised a duplicate-key error and the ENTIRE merge aborted. Fixed with the
-- same delete-the-duplicate-then-update pattern already used for attendance /
-- paysplit_participants / paysplit_expense_payers / schedule_attendees /
-- paysplit_opening_balances. Full function re-created below.
--
-- Verified via rolled-back E2E: a merge with colliding session_rotations + both
-- share links now completes (keep ends with 2 rotations / 1 share link), and the
-- three guards still fire (non-manager, two linked accounts, shared match).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.merge_players(p_keep_id uuid, p_remove_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_club uuid; v_remove_club uuid; v_keep_user uuid; v_remove_user uuid; v_shared int;
BEGIN
  IF p_keep_id = p_remove_id THEN RAISE EXCEPTION 'Pick two different players'; END IF;
  SELECT club_id, user_id INTO v_club,        v_keep_user   FROM players WHERE id = p_keep_id;
  SELECT club_id, user_id INTO v_remove_club, v_remove_user FROM players WHERE id = p_remove_id;
  IF v_club IS NULL OR v_remove_club IS NULL THEN RAISE EXCEPTION 'Player not found'; END IF;
  IF v_club <> v_remove_club THEN RAISE EXCEPTION 'Both players must be in the same club'; END IF;
  IF NOT is_manager(v_club) THEN RAISE EXCEPTION 'Only club managers can merge players'; END IF;
  IF v_keep_user IS NOT NULL AND v_remove_user IS NOT NULL THEN
    RAISE EXCEPTION 'Both players have linked accounts — merging two separate accounts is not supported here';
  END IF;

  -- Same-match conflict guard
  SELECT count(*) INTO v_shared FROM (
    SELECT ms.match_id FROM match_participants mp JOIN match_sides ms ON ms.id = mp.match_side_id
    WHERE mp.player_id IN (p_keep_id, p_remove_id)
    GROUP BY ms.match_id HAVING count(DISTINCT mp.player_id) = 2
  ) x;
  IF v_shared > 0 THEN
    RAISE EXCEPTION 'These two players share % match(es) (they played in the same game) and cannot be merged. Fix/delete those matches first.', v_shared;
  END IF;

  -- Reassign references remove -> keep, de-duping on uniqueness
  UPDATE match_participants SET player_id = p_keep_id WHERE player_id = p_remove_id;

  DELETE FROM attendance a WHERE a.player_id = p_remove_id
    AND EXISTS (SELECT 1 FROM attendance b WHERE b.player_id = p_keep_id AND b.played_on = a.played_on);
  UPDATE attendance SET player_id = p_keep_id WHERE player_id = p_remove_id;

  DELETE FROM paysplit_participants r WHERE r.player_id = p_remove_id
    AND EXISTS (SELECT 1 FROM paysplit_participants k WHERE k.expense_id = r.expense_id AND k.player_id = p_keep_id);
  UPDATE paysplit_participants SET player_id = p_keep_id WHERE player_id = p_remove_id;

  UPDATE paysplit_expenses SET paid_player_id = p_keep_id WHERE paid_player_id = p_remove_id;

  DELETE FROM paysplit_expense_payers r WHERE r.player_id = p_remove_id
    AND EXISTS (SELECT 1 FROM paysplit_expense_payers k WHERE k.expense_id = r.expense_id AND k.player_id = p_keep_id);
  UPDATE paysplit_expense_payers SET player_id = p_keep_id WHERE player_id = p_remove_id;

  DELETE FROM paysplit_settlements
    WHERE (from_player_id = p_remove_id AND to_player_id = p_keep_id)
       OR (from_player_id = p_keep_id AND to_player_id = p_remove_id);
  UPDATE paysplit_settlements SET from_player_id = p_keep_id WHERE from_player_id = p_remove_id;
  UPDATE paysplit_settlements SET to_player_id   = p_keep_id WHERE to_player_id   = p_remove_id;

  UPDATE wallet_contributions SET player_id = p_keep_id WHERE player_id = p_remove_id;

  UPDATE paysplit_opening_balances k SET amount = k.amount + r.amount
    FROM paysplit_opening_balances r
    WHERE k.player_id = p_keep_id AND r.player_id = p_remove_id AND k.club_id = r.club_id;
  DELETE FROM paysplit_opening_balances r WHERE r.player_id = p_remove_id
    AND EXISTS (SELECT 1 FROM paysplit_opening_balances k WHERE k.player_id = p_keep_id AND k.club_id = r.club_id);
  UPDATE paysplit_opening_balances SET player_id = p_keep_id WHERE player_id = p_remove_id;

  DELETE FROM schedule_attendees r WHERE r.player_id = p_remove_id
    AND EXISTS (SELECT 1 FROM schedule_attendees k WHERE k.schedule_id = r.schedule_id AND k.player_id = p_keep_id);
  UPDATE schedule_attendees SET player_id = p_keep_id WHERE player_id = p_remove_id;

  -- session_rotations: UNIQUE (club_id, session_date, player_id) → dedupe before update  [v140]
  DELETE FROM session_rotations r WHERE r.player_id = p_remove_id
    AND EXISTS (SELECT 1 FROM session_rotations k
                WHERE k.club_id = r.club_id AND k.session_date = r.session_date AND k.player_id = p_keep_id);
  UPDATE session_rotations SET player_id = p_keep_id WHERE player_id = p_remove_id;

  -- share_links: UNIQUE (player_id) → if the survivor already has one, drop the duplicate's  [v140]
  DELETE FROM share_links r WHERE r.player_id = p_remove_id
    AND EXISTS (SELECT 1 FROM share_links k WHERE k.player_id = p_keep_id);
  UPDATE share_links SET player_id = p_keep_id WHERE player_id = p_remove_id;

  UPDATE club_invites SET guest_player_id = p_keep_id WHERE guest_player_id = p_remove_id;

  -- If the survivor is a guest and the removed one had the account, move the account across.
  IF v_keep_user IS NULL AND v_remove_user IS NOT NULL THEN
    UPDATE players SET user_id = v_remove_user, pending_email = NULL WHERE id = p_keep_id;
  END IF;

  DELETE FROM players WHERE id = p_remove_id;

  PERFORM _replay_club_elo(v_club);
  RETURN jsonb_build_object('ok', true, 'merged_into', p_keep_id);
END;
$function$;
