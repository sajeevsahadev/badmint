-- =====================================================================
-- Badminton 360 v132 — Accurate login country + admin Users clubs/country
-- Applied to prod via Supabase MCP; archived here for rebuild parity.
--
-- Task 1: Login Audit showed wrong COUNTRY (e.g. "Abu Dhabi, United States").
--   Root cause: country came from the CLIENT (useGeo). When ipapi.co is
--   rate-limited/blocked it falls back to the BROWSER LOCALE (en-US -> United
--   States, en-GB -> United Kingdom), so country was garbage while the city
--   (also from ipapi) was often right. Fix: take the country server-side from
--   Cloudflare's `cf-ipcountry` request header (accurate, no rate limit, no
--   client trust) and store the 2-letter code in app_sessions.country_code.
--   The frontend renders the name+flag from the code. City/region still come
--   from the client (Cloudflare free doesn't give city).
-- Task 2: Admin Users list now shows each user's clubs + last sign-in country.
-- =====================================================================

ALTER TABLE app_sessions ADD COLUMN IF NOT EXISTS country_code text;   -- ISO-2 from Cloudflare

-- ── create_session: authoritative country from Cloudflare cf-ipcountry ──
CREATE OR REPLACE FUNCTION public.create_session(
  p_user_agent text DEFAULT NULL, p_club_id uuid DEFAULT NULL,
  p_country text DEFAULT NULL, p_city text DEFAULT NULL, p_region text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_id   uuid;
  v_ip   text;
  v_club uuid;
  v_cc   text;
BEGIN
  BEGIN
    v_ip := current_setting('request.headers', true)::json->>'x-real-ip';
    IF v_ip IS NULL OR v_ip = '' THEN
      v_ip := split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1);
    END IF;
  EXCEPTION WHEN others THEN v_ip := NULL;
  END;

  -- Authoritative country from Cloudflare (overrides the unreliable client value)
  BEGIN
    v_cc := upper(nullif(trim(current_setting('request.headers', true)::json->>'cf-ipcountry'), ''));
    IF v_cc IN ('XX', 'T1') THEN v_cc := NULL; END IF;   -- CF: unknown / Tor
  EXCEPTION WHEN others THEN v_cc := NULL;
  END;

  v_club := p_club_id;
  IF v_club IS NULL THEN
    SELECT cm.club_id INTO v_club
    FROM club_members cm
    WHERE cm.user_id = auth.uid()
    ORDER BY CASE cm.role WHEN 'owner' THEN 0 WHEN 'manager' THEN 1 ELSE 2 END, cm.joined_at ASC
    LIMIT 1;
  END IF;

  INSERT INTO app_sessions(user_id, ip_address, user_agent, club_id, country, city, region, country_code)
  VALUES (
    auth.uid(),
    nullif(trim(v_ip), ''),
    coalesce(p_user_agent, 'unknown'),
    v_club,
    nullif(trim(p_country), ''),     -- kept for backward-compat; display prefers country_code
    nullif(trim(p_city), ''),
    nullif(trim(p_region), ''),
    v_cc
  )
  RETURNING id INTO v_id;

  INSERT INTO user_profiles(user_id, last_seen_at, updated_at)
  VALUES (auth.uid(), now(), now())
  ON CONFLICT (user_id) DO UPDATE SET last_seen_at = now(), updated_at = now();

  RETURN v_id;
END;
$function$;

-- ── admin_get_sessions: expose country_code ──
CREATE OR REPLACE FUNCTION public.admin_get_sessions(p_limit integer DEFAULT 200)
RETURNS TABLE(session_id uuid, user_id uuid, full_name text, email text, phone text,
              ip_address text, user_agent text, country text, city text, region text,
              country_code text, club_name text,
              logged_in_at timestamptz, last_active_at timestamptz, is_active boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  RETURN QUERY
  SELECT
    s.id, s.user_id,
    COALESCE(up.full_name, up.nickname, split_part(u.email, '@', 1)) AS full_name,
    u.email::text, up.phone, s.ip_address, s.user_agent,
    s.country, s.city, s.region, s.country_code, c.name AS club_name,
    s.logged_in_at, s.last_active_at, s.is_active
  FROM app_sessions s
  LEFT JOIN auth.users u     ON u.id = s.user_id
  LEFT JOIN user_profiles up ON up.user_id = s.user_id
  LEFT JOIN clubs c          ON c.id = s.club_id
  ORDER BY s.logged_in_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 1000));
END;
$function$;

-- ── get_all_users: add clubs joined + last sign-in country ──
DROP FUNCTION IF EXISTS get_all_users(text);
CREATE OR REPLACE FUNCTION get_all_users(p_search text DEFAULT NULL)
RETURNS TABLE(user_id uuid, email text, full_name text, nickname text,
              last_sign_in timestamptz, created_at timestamptz, roles jsonb,
              tournaments_created bigint, login_count bigint, last_ip text, last_user_agent text,
              deactivated_at timestamptz, email_suppressed boolean,
              clubs jsonb, country_code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  WITH session_stats AS (
    SELECT s.user_id, COUNT(*)::bigint AS login_count,
           (array_agg(s.ip_address ORDER BY s.logged_in_at DESC))[1] AS last_ip,
           (array_agg(s.user_agent  ORDER BY s.logged_in_at DESC))[1] AS last_ua,
           (array_agg(s.country_code ORDER BY s.logged_in_at DESC) FILTER (WHERE s.country_code IS NOT NULL))[1] AS last_cc
    FROM app_sessions s GROUP BY s.user_id)
  SELECT u.id, u.email::text,
    COALESCE(up.full_name, u.raw_user_meta_data->>'full_name')::text, up.nickname::text,
    u.last_sign_in_at, u.created_at,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('role', ar.role, 'tournament_quota', ar.tournament_quota,
              'facility_id', ar.facility_id, 'granted_at', ar.granted_at, 'notes', ar.notes) ORDER BY ar.granted_at)
              FROM app_roles ar WHERE ar.user_id = u.id), '[]'::jsonb),
    (SELECT COUNT(*) FROM tournaments t WHERE t.created_by = u.id)::bigint,
    COALESCE(ss.login_count, 0)::bigint, ss.last_ip::text, ss.last_ua::text,
    up.deactivated_at,
    EXISTS (SELECT 1 FROM email_suppression es WHERE es.email = lower(u.email)),
    COALESCE((SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'role', cm.role) ORDER BY c.name)
              FROM club_members cm JOIN clubs c ON c.id = cm.club_id
              WHERE cm.user_id = u.id AND c.deleted_at IS NULL), '[]'::jsonb) AS clubs,
    ss.last_cc::text AS country_code
  FROM auth.users u
  LEFT JOIN user_profiles up ON up.user_id = u.id
  LEFT JOIN session_stats ss ON ss.user_id = u.id
  WHERE p_search IS NULL OR u.email ILIKE '%'||p_search||'%' OR up.nickname ILIKE '%'||p_search||'%'
     OR up.full_name ILIKE '%'||p_search||'%' OR (u.raw_user_meta_data->>'full_name') ILIKE '%'||p_search||'%'
  ORDER BY u.created_at DESC LIMIT 100;
END;
$$;
GRANT EXECUTE ON FUNCTION get_all_users(text) TO authenticated;
