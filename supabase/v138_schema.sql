-- =====================================================================
-- Badminton 360 v138 — Auto-email the invite when linking a guest player
-- Applied to prod via Supabase MCP; archived for rebuild parity.
--
-- Before: "Link Account" on an unregistered email saved the pending link but left
-- the manager to copy/WhatsApp the invite by hand.
-- Now: the system emails the invite automatically (send-club-invite-email edge fn).
-- The registered-email path already auto-emailed via send-club-added-email (v137).
--
-- This RPC supplies the club + player names for that email AND authorizes the send:
-- only a manager of the club (or an app_admin) may trigger it, so a logged-in
-- non-manager can't spam arbitrary addresses with "you've been added to <club>".
-- =====================================================================
CREATE OR REPLACE FUNCTION public.get_club_invite_notice(p_club_id uuid, p_player_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v jsonb;
BEGIN
  IF NOT (is_manager(p_club_id) OR is_app_admin()) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  SELECT jsonb_build_object('club_name', c.name, 'player_name', p.display_name)
    INTO v
  FROM clubs c
  LEFT JOIN players p ON p.id = p_player_id AND p.club_id = p_club_id
  WHERE c.id = p_club_id;
  RETURN v;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_club_invite_notice(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_club_invite_notice(uuid, uuid) TO authenticated;
