-- =====================================================================
-- Badminton 360 v124 — Login audit: fall back to the caller's home club
-- Run in Supabase SQL Editor. (Applied to prod.)
--
-- The login audit (admin_get_sessions) shows the club captured at login. Some
-- rows show "—" because the client passed no club_id (e.g. a member who hadn't
-- selected a club yet on a fresh device). This updates create_session so that
-- when no club is supplied it falls back to the caller's home club — preferring
-- one they own/manage, else their earliest-joined club — so the audit reliably
-- shows the login-time club for anyone who belongs to a club. Users in no club
-- still record NULL (correctly shown as "—"). Only affects logins from now on;
-- existing session rows are not backfilled.
-- =====================================================================

CREATE OR REPLACE FUNCTION create_session(
  p_user_agent text DEFAULT NULL,
  p_club_id    uuid DEFAULT NULL,
  p_country    text DEFAULT NULL,
  p_city       text DEFAULT NULL,
  p_region     text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id   uuid;
  v_ip   text;
  v_club uuid;
BEGIN
  -- Real client IP from PostgREST-forwarded headers
  BEGIN
    v_ip := current_setting('request.headers', true)::json->>'x-real-ip';
    IF v_ip IS NULL OR v_ip = '' THEN
      v_ip := split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1);
    END IF;
  EXCEPTION WHEN others THEN v_ip := NULL;
  END;

  -- Prefer the club the client reported; otherwise fall back to the caller's
  -- home club (owned/managed first, then earliest joined).
  v_club := p_club_id;
  IF v_club IS NULL THEN
    SELECT cm.club_id INTO v_club
    FROM club_members cm
    WHERE cm.user_id = auth.uid()
    ORDER BY CASE cm.role WHEN 'owner' THEN 0 WHEN 'manager' THEN 1 ELSE 2 END, cm.joined_at ASC
    LIMIT 1;
  END IF;

  INSERT INTO app_sessions(user_id, ip_address, user_agent, club_id, country, city, region)
  VALUES (
    auth.uid(),
    nullif(trim(v_ip), ''),
    coalesce(p_user_agent, 'unknown'),
    v_club,
    nullif(trim(p_country), ''),
    nullif(trim(p_city), ''),
    nullif(trim(p_region), '')
  )
  RETURNING id INTO v_id;

  INSERT INTO user_profiles(user_id, last_seen_at, updated_at)
  VALUES (auth.uid(), now(), now())
  ON CONFLICT (user_id) DO UPDATE SET last_seen_at = now(), updated_at = now();

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_session(text, uuid, text, text, text) TO authenticated;
