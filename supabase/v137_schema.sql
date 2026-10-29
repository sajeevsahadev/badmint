-- =====================================================================
-- Badminton 360 v137 — Merge duplicate players + prevent new ones
-- Applied to prod via Supabase MCP; full bodies in migration history.
--
-- Problem: one person can become two `players` rows in a club (a guest the owner
-- created + the account-linked row from them self-joining), splitting Elo/history.
--
-- Delivered:
--   * _replay_club_elo(club_id)  — reusable reset+replay (same math as delete_match).
--   * merge_players(keep_id, remove_id) — folds remove -> keep in the same club:
--       authz is_manager()/app_admin; refuses if BOTH have accounts; BLOCKS when the
--       two share a match (played together); reassigns every player_id reference
--       (match_participants, attendance, paysplit_participants/expenses/payers/
--       settlements/opening_balances, wallet_contributions, schedule_attendees,
--       session_rotations, share_links, club_invites.guest_player_id), de-duping on
--       unique keys (attendance/day, expense/player, opening balance summed, self-
--       settlements dropped); moves the account to the survivor if it was a guest;
--       deletes the duplicate; then _replay_club_elo. Manage → guest row "Merge".
--   * approve_join — now REUSES a guest player pre-linked to the joiner's email
--       (players.pending_email) instead of creating a second row (prevention).
--   * get_club_link_notice(player_id) — recipient for the "you've been added to
--       <club>" email (invites pref + not deactivated/suppressed); used by the
--       send-club-added-email edge fn, fired when an account is linked.
-- =====================================================================

-- approve_join: reuse a pending-email guest player instead of making a duplicate
CREATE OR REPLACE FUNCTION public.approve_join(p_request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare v_club uuid; v_user uuid; v_name text; v_email text; v_linked int;
begin
  select club_id, user_id, user_name into v_club, v_user, v_name from join_requests where id = p_request_id;
  if not is_manager(v_club) then raise exception 'Not authorized'; end if;
  insert into club_members(club_id, user_id, role) values (v_club, v_user, 'player') on conflict do nothing;
  select lower(email) into v_email from auth.users where id = v_user;
  update players set user_id = v_user, pending_email = null
   where club_id = v_club and user_id is null and v_email is not null and lower(pending_email) = v_email;
  get diagnostics v_linked = row_count;
  if v_linked = 0 then
    insert into players(club_id, user_id, display_name)
      select v_club, v_user, v_name
      where not exists (select 1 from players where club_id = v_club and user_id = v_user);
  end if;
  update join_requests set status = 'approved' where id = p_request_id;
end;
$function$;

-- Email recipient for the link notice (full merge_players / _replay_club_elo bodies
-- are in the Supabase migration history: v137_merge_players_and_link_prevention).
CREATE OR REPLACE FUNCTION public.get_club_link_notice(p_player_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT jsonb_build_object(
    'email', u.email,
    'name',  COALESCE(up.nickname, up.full_name, split_part(u.email, '@', 1)),
    'club_name', c.name)
  FROM players p
  JOIN auth.users u ON u.id = p.user_id
  JOIN clubs c ON c.id = p.club_id
  LEFT JOIN user_profiles up ON up.user_id = p.user_id
  WHERE p.id = p_player_id
    AND u.email IS NOT NULL
    AND up.deactivated_at IS NULL
    AND COALESCE((up.email_prefs->>'invites')::boolean, true)
    AND NOT EXISTS (SELECT 1 FROM email_suppression es WHERE es.email = lower(u.email));
$function$;
REVOKE ALL ON FUNCTION public.get_club_link_notice(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_club_link_notice(uuid) TO service_role;
