-- v99_delete_player
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Permanently delete a player, but ONLY when they have no match history and no
-- Split Pay activity (so nothing that references them is orphaned). Owner/manager
-- only. For a linked member it also removes their club membership + join request
-- (full removal). Attendance and schedule votes are cleaned up automatically.
CREATE OR REPLACE FUNCTION public.delete_player(p_player_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_club uuid;
  v_user uuid;
BEGIN
  SELECT club_id, user_id INTO v_club, v_user FROM players WHERE id = p_player_id;
  IF v_club IS NULL THEN RAISE EXCEPTION 'Player not found'; END IF;

  IF NOT is_manager(v_club) THEN
    RAISE EXCEPTION 'Only club managers or owners can delete players';
  END IF;

  IF EXISTS (SELECT 1 FROM match_participants WHERE player_id = p_player_id) THEN
    RAISE EXCEPTION 'This player has match history — deactivate them instead of deleting.';
  END IF;

  IF EXISTS (SELECT 1 FROM paysplit_participants     WHERE player_id = p_player_id)
  OR EXISTS (SELECT 1 FROM paysplit_expense_payers   WHERE player_id = p_player_id)
  OR EXISTS (SELECT 1 FROM wallet_contributions      WHERE player_id = p_player_id)
  OR EXISTS (SELECT 1 FROM paysplit_opening_balances WHERE player_id = p_player_id) THEN
    RAISE EXCEPTION 'This player has Split Pay activity and cannot be deleted.';
  END IF;

  -- Clean up derived / ephemeral references, then the player row.
  DELETE FROM attendance         WHERE player_id = p_player_id;
  DELETE FROM schedule_attendees WHERE player_id = p_player_id;
  DELETE FROM players            WHERE id = p_player_id;

  -- Linked member → also remove membership + any join request (the club-must-keep-
  -- one-owner trigger still protects against removing the last owner).
  IF v_user IS NOT NULL THEN
    DELETE FROM club_members  WHERE club_id = v_club AND user_id = v_user;
    DELETE FROM join_requests WHERE club_id = v_club AND user_id = v_user;
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.delete_player(uuid) TO authenticated;;
