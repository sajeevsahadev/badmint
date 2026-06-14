-- =====================================================================
-- Badmint v26 — Guest player account linking via invite
-- Run once in Supabase SQL Editor
-- =====================================================================

-- 1. Add guest_player_id to club_invites so we can link the invite to an existing guest player row
ALTER TABLE club_invites
  ADD COLUMN IF NOT EXISTS guest_player_id uuid REFERENCES players(id) ON DELETE SET NULL;

-- 2. RPC: manager sends an invite link tied to a specific guest player
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

  v_token := encode(gen_random_bytes(32), 'hex');

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

-- 3. Replace accept_invite to handle guest_player_id:
--    if set → link existing player row to the new account
--    if null → normal path (create new player row)
CREATE OR REPLACE FUNCTION accept_invite(p_token text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_invite club_invites%ROWTYPE;
BEGIN
  SELECT * INTO v_invite
  FROM club_invites
  WHERE token = p_token AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invite not found or already used';
  END IF;

  IF v_invite.expires_at < now() THEN
    RAISE EXCEPTION 'Invite has expired';
  END IF;

  -- Mark accepted
  UPDATE club_invites SET status = 'accepted' WHERE id = v_invite.id;

  -- Add to club_members (idempotent)
  INSERT INTO club_members (club_id, user_id, role)
  VALUES (v_invite.club_id, auth.uid(), 'player')
  ON CONFLICT (club_id, user_id) DO NOTHING;

  IF v_invite.guest_player_id IS NOT NULL THEN
    -- Link the existing guest player row to this Google account
    UPDATE players
    SET user_id = auth.uid()
    WHERE id = v_invite.guest_player_id
      AND club_id = v_invite.club_id
      AND user_id IS NULL;
  ELSE
    -- Normal invite: create a new player row if not already present
    INSERT INTO players (club_id, display_name, user_id)
    SELECT
      v_invite.club_id,
      COALESCE(
        (SELECT COALESCE(nickname, full_name) FROM user_profiles WHERE user_id = auth.uid()),
        split_part(v_invite.email, '@', 1)
      ),
      auth.uid()
    WHERE NOT EXISTS (
      SELECT 1 FROM players WHERE club_id = v_invite.club_id AND user_id = auth.uid()
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_invite(text) TO authenticated;
