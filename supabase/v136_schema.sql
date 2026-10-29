-- =====================================================================
-- Badminton 360 v136 — Pending account link (auto-link on signup)
-- Applied to prod via Supabase MCP; archived for rebuild parity.
--
-- "Link Account" on a guest player used to fail with "not registered" when the
-- email had no account yet. Now it SAVES the email on the guest player
-- (players.pending_email); when that person signs in with that email,
-- claim_my_pending_links() (called from App.vue on every login) links them to
-- the guest player automatically — sets user_id, adds club_members, approves any
-- pending join request, accepts any pending invite. Skips clubs where the user
-- already has a linked player (that's the duplicate case → needs a merge).
-- =====================================================================
ALTER TABLE players ADD COLUMN IF NOT EXISTS pending_email text;
CREATE INDEX IF NOT EXISTS idx_players_pending_email ON players(lower(pending_email)) WHERE pending_email IS NOT NULL AND user_id IS NULL;

CREATE OR REPLACE FUNCTION public.link_guest_player(p_club_id uuid, p_player_id uuid, p_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_user_id uuid; v_display text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid() AND role IN ('owner','manager'))
     AND NOT is_app_admin() THEN
    RAISE EXCEPTION 'Only club managers can link accounts';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id AND club_id = p_club_id AND user_id IS NULL) THEN
    RAISE EXCEPTION 'Player not found in this club or already has an account linked';
  END IF;
  SELECT id INTO v_user_id FROM auth.users WHERE lower(email) = lower(trim(p_email)) LIMIT 1;
  IF v_user_id IS NULL THEN
    UPDATE players SET pending_email = lower(trim(p_email)) WHERE id = p_player_id;
    RETURN jsonb_build_object('linked', false, 'reason', 'pending', 'pending_email', lower(trim(p_email)));
  END IF;
  IF EXISTS (SELECT 1 FROM players WHERE club_id = p_club_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'This account is already linked to another player in this club';
  END IF;
  INSERT INTO club_members (club_id, user_id, role) VALUES (p_club_id, v_user_id, 'player')
  ON CONFLICT (club_id, user_id) DO NOTHING;
  UPDATE players SET user_id = v_user_id, pending_email = NULL WHERE id = p_player_id AND user_id IS NULL;
  UPDATE join_requests SET status = 'approved' WHERE club_id = p_club_id AND user_id = v_user_id AND status = 'pending';
  UPDATE club_invites SET status = 'expired' WHERE guest_player_id = p_player_id AND status = 'pending';
  SELECT COALESCE(nickname, full_name) INTO v_display FROM user_profiles WHERE user_id = v_user_id;
  RETURN jsonb_build_object('linked', true, 'display_name', v_display);
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_my_pending_links()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_uid uuid := auth.uid(); v_email text; v_count int := 0; r record;
BEGIN
  IF v_uid IS NULL THEN RETURN 0; END IF;
  SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;
  IF v_email IS NULL THEN RETURN 0; END IF;
  FOR r IN
    SELECT p.id AS player_id, p.club_id FROM players p
    WHERE p.user_id IS NULL AND lower(p.pending_email) = v_email
      AND NOT EXISTS (SELECT 1 FROM players p2 WHERE p2.club_id = p.club_id AND p2.user_id = v_uid)
  LOOP
    INSERT INTO club_members (club_id, user_id, role) VALUES (r.club_id, v_uid, 'player') ON CONFLICT (club_id, user_id) DO NOTHING;
    UPDATE players SET user_id = v_uid, pending_email = NULL WHERE id = r.player_id AND user_id IS NULL;
    UPDATE join_requests SET status = 'approved' WHERE club_id = r.club_id AND user_id = v_uid AND status = 'pending';
    UPDATE club_invites SET status = 'accepted' WHERE guest_player_id = r.player_id AND status = 'pending';
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.claim_my_pending_links() TO authenticated;
