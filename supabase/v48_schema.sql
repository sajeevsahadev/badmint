-- =====================================================================
-- Badminton 360 v48 — Guest player linking fixes
-- Run in Supabase SQL Editor (after v47_schema.sql)
--
-- Fix 1: invite_guest_player crashed with
--        "function gen_random_bytes(integer) does not exist".
--        pgcrypto lives in the `extensions` schema on Supabase, but the
--        function runs with SET search_path = public, so the unqualified
--        call never resolves. (The club_invites column DEFAULT keeps
--        working because defaults bind the function OID at creation.)
--        Fix: generate the token from gen_random_uuid() (pg_catalog,
--        always visible) — two UUIDs = 64 hex chars, same shape as
--        encode(gen_random_bytes(32),'hex').
--
-- Fix 2: NEW link_guest_player() — when the person has ALREADY signed
--        up with Google, the manager can link the guest player row to
--        their account instantly: no invite link, no user-side approval.
--        Managers already have the power to admit members (approve_join /
--        invite_member), so direct linking grants nothing new.
-- =====================================================================

-- ── Fix 1: invite_guest_player without pgcrypto ──────────────────────
CREATE OR REPLACE FUNCTION invite_guest_player(
  p_club_id   uuid,
  p_player_id uuid,
  p_email     text
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_token text;
BEGIN
  -- Manager/owner only
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid() AND role IN ('owner', 'manager')
  ) THEN
    RAISE EXCEPTION 'Only club managers can send invites';
  END IF;

  -- Player must be in this club and not yet linked to any account
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE id = p_player_id AND club_id = p_club_id AND user_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Player not found in this club or already has an account linked';
  END IF;

  -- 64 hex chars without pgcrypto (search_path=public can't see extensions.gen_random_bytes)
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

  INSERT INTO club_invites (club_id, email, token, status, invited_by, expires_at, guest_player_id)
  VALUES (
    p_club_id,
    lower(trim(p_email)),
    v_token,
    'pending',
    auth.uid(),
    now() + interval '7 days',
    p_player_id
  );

  RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION invite_guest_player(uuid, uuid, text) TO authenticated;

-- ── Fix 2: link_guest_player — instant link for registered users ─────
-- Returns jsonb:
--   { linked: true,  display_name: ... }   → done, player claimed
--   { linked: false, reason: 'not_registered' } → fall back to invite link
CREATE OR REPLACE FUNCTION link_guest_player(
  p_club_id   uuid,
  p_player_id uuid,
  p_email     text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid;
  v_display text;
BEGIN
  -- Manager/owner only
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid() AND role IN ('owner', 'manager')
  ) THEN
    RAISE EXCEPTION 'Only club managers can link accounts';
  END IF;

  -- Player must be in this club and not yet linked
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE id = p_player_id AND club_id = p_club_id AND user_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Player not found in this club or already has an account linked';
  END IF;

  -- Look up a registered account by email
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE lower(email) = lower(trim(p_email))
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('linked', false, 'reason', 'not_registered');
  END IF;

  -- One player per account per club
  IF EXISTS (
    SELECT 1 FROM players WHERE club_id = p_club_id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'This account is already linked to another player in this club';
  END IF;

  -- Membership (idempotent) + claim the player row (Elo history preserved)
  INSERT INTO club_members (club_id, user_id, role)
  VALUES (p_club_id, v_user_id, 'player')
  ON CONFLICT (club_id, user_id) DO NOTHING;

  UPDATE players SET user_id = v_user_id
  WHERE id = p_player_id AND user_id IS NULL;

  -- Tidy up: a pending join request is now moot; stale invite links tied
  -- to this guest row must not be claimable by someone else later.
  UPDATE join_requests SET status = 'approved'
  WHERE club_id = p_club_id AND user_id = v_user_id AND status = 'pending';

  UPDATE club_invites SET status = 'expired'
  WHERE guest_player_id = p_player_id AND status = 'pending';

  SELECT COALESCE(nickname, full_name) INTO v_display
  FROM user_profiles WHERE user_id = v_user_id;

  RETURN jsonb_build_object('linked', true, 'display_name', v_display);
END;
$$;

GRANT EXECUTE ON FUNCTION link_guest_player(uuid, uuid, text) TO authenticated;
