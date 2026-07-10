-- =====================================================================
-- Badminton 360 v56 — Security audit: richer login sessions + admin view
-- Run in Supabase SQL Editor. (Applied to prod.)
--
-- app_sessions already stores the real client IP (x-real-ip / x-forwarded-for)
-- and user_agent. This migration adds the club and IP location captured at
-- login, and an admin-only RPC that lists logins newest-first with the
-- identifying detail an admin needs to police access:
--   name, email, phone, IP, device (from UA), location, club, time.
-- =====================================================================

-- ── 1. New columns on app_sessions ──────────────────────────────────
ALTER TABLE app_sessions ADD COLUMN IF NOT EXISTS club_id uuid REFERENCES clubs(id) ON DELETE SET NULL;
ALTER TABLE app_sessions ADD COLUMN IF NOT EXISTS country text;
ALTER TABLE app_sessions ADD COLUMN IF NOT EXISTS city    text;
ALTER TABLE app_sessions ADD COLUMN IF NOT EXISTS region  text;

CREATE INDEX IF NOT EXISTS idx_app_sessions_logged_in_at ON app_sessions(logged_in_at DESC);

-- ── 2. create_session: capture club + IP location too ───────────────
-- Drop the old single-arg overload so the client's 1-arg PostgREST call
-- can't become ambiguous against the new defaulted signature.
DROP FUNCTION IF EXISTS create_session(text);
DROP FUNCTION IF EXISTS create_session(text, uuid, text, text, text);

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
  v_id uuid;
  v_ip text;
BEGIN
  -- Real client IP from PostgREST-forwarded headers
  BEGIN
    v_ip := current_setting('request.headers', true)::json->>'x-real-ip';
    IF v_ip IS NULL OR v_ip = '' THEN
      v_ip := split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1);
    END IF;
  EXCEPTION WHEN others THEN v_ip := NULL;
  END;

  INSERT INTO app_sessions(user_id, ip_address, user_agent, club_id, country, city, region)
  VALUES (
    auth.uid(),
    nullif(trim(v_ip), ''),
    coalesce(p_user_agent, 'unknown'),
    p_club_id,
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

-- ── 3. admin_get_sessions: newest-first login audit (admin only) ────
DROP FUNCTION IF EXISTS admin_get_sessions(int);
CREATE OR REPLACE FUNCTION admin_get_sessions(p_limit int DEFAULT 200)
RETURNS TABLE(
  session_id   uuid,
  user_id      uuid,
  full_name    text,
  email        text,
  phone        text,
  ip_address   text,
  user_agent   text,
  country      text,
  city         text,
  region       text,
  club_name    text,
  logged_in_at timestamptz,
  last_active_at timestamptz,
  is_active    boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_app_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.user_id,
    COALESCE(up.full_name, up.nickname, split_part(u.email, '@', 1)) AS full_name,
    u.email::text,
    up.phone,
    s.ip_address,
    s.user_agent,
    s.country,
    s.city,
    s.region,
    c.name AS club_name,
    s.logged_in_at,
    s.last_active_at,
    s.is_active
  FROM app_sessions s
  LEFT JOIN auth.users u     ON u.id = s.user_id
  LEFT JOIN user_profiles up ON up.user_id = s.user_id
  LEFT JOIN clubs c          ON c.id = s.club_id
  ORDER BY s.logged_in_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 1000));
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_sessions(int) TO authenticated;
