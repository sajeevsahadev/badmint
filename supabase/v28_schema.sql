-- =====================================================================
-- Badmint v28 — Admin panel fixes + enhancements
-- Run once in Supabase SQL Editor
-- Fixes: get_all_users signature mismatch, admin_get_clubs duplicates,
--        admin_get_facilities silent fail; adds admin_create_facility
-- =====================================================================

-- ── Fix 1: get_all_users — add session stats (login count + last IP) ──
-- DROP required because we're adding columns to the RETURNS TABLE signature.
-- Without DROP, CREATE OR REPLACE rejects a return-type change.
DROP FUNCTION IF EXISTS get_all_users(text);
CREATE FUNCTION get_all_users(p_search text DEFAULT NULL)
RETURNS TABLE (
  user_id             uuid,
  email               text,
  full_name           text,
  nickname            text,
  last_sign_in        timestamptz,
  created_at          timestamptz,
  roles               jsonb,
  tournaments_created bigint,
  login_count         bigint,
  last_ip             text,
  last_user_agent     text
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  WITH session_stats AS (
    SELECT
      s.user_id,
      COUNT(*)::bigint                                          AS login_count,
      (array_agg(s.ip_address ORDER BY s.logged_in_at DESC))[1] AS last_ip,
      (array_agg(s.user_agent  ORDER BY s.logged_in_at DESC))[1] AS last_ua
    FROM app_sessions s
    GROUP BY s.user_id
  )
  SELECT
    u.id,
    u.email::text,
    COALESCE(up.full_name, u.raw_user_meta_data->>'full_name')::text,
    up.nickname::text,
    u.last_sign_in_at,
    u.created_at,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'role',             ar.role,
        'tournament_quota', ar.tournament_quota,
        'facility_id',      ar.facility_id,
        'granted_at',       ar.granted_at,
        'notes',            ar.notes
      ) ORDER BY ar.granted_at)
      FROM app_roles ar WHERE ar.user_id = u.id
    ), '[]'::jsonb),
    (SELECT COUNT(*) FROM tournaments t WHERE t.created_by = u.id)::bigint,
    COALESCE(ss.login_count, 0)::bigint,
    ss.last_ip::text,
    ss.last_ua::text
  FROM auth.users u
  LEFT JOIN user_profiles up ON up.user_id = u.id
  LEFT JOIN session_stats ss ON ss.user_id = u.id
  WHERE p_search IS NULL
     OR u.email                            ILIKE '%' || p_search || '%'
     OR up.nickname                        ILIKE '%' || p_search || '%'
     OR up.full_name                       ILIKE '%' || p_search || '%'
     OR (u.raw_user_meta_data->>'full_name') ILIKE '%' || p_search || '%'
  ORDER BY u.created_at DESC
  LIMIT 100;
END;
$$;
GRANT EXECUTE ON FUNCTION get_all_users(text) TO authenticated;

-- ── Fix 2: admin_get_clubs — eliminate duplicate rows ─────────────────
-- Root cause: clubs with multiple owners (after role promotions via v25
-- trigger) caused one row per owner in the old query.
-- Fix: DISTINCT ON (c.id) keeps exactly one row per club.
DROP FUNCTION IF EXISTS admin_get_clubs();
CREATE FUNCTION admin_get_clubs()
RETURNS TABLE (
  club_id      uuid,
  name         text,
  created_at   timestamptz,
  owner_email  text,
  owner_name   text,
  member_count bigint,
  matches_30d  bigint,
  club_score   numeric,
  club_rank    bigint
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  SELECT DISTINCT ON (c.id)
    c.id,
    c.name,
    c.created_at,
    au.email::text,
    COALESCE(up.full_name, (au.raw_user_meta_data->>'full_name'))::text,
    COALESCE(cr.total_members, 0)::bigint,
    COALESCE(cr.matches_30d,   0)::bigint,
    COALESCE(cr.club_score,    0)::numeric,
    cr.club_rank
  FROM clubs c
  LEFT JOIN v_club_rankings cr ON cr.club_id = c.id
  LEFT JOIN club_members cm    ON cm.club_id  = c.id AND cm.role = 'owner'
  LEFT JOIN auth.users au      ON au.id        = cm.user_id
  LEFT JOIN user_profiles up   ON up.user_id   = cm.user_id
  ORDER BY c.id, COALESCE(cr.club_rank, 999999);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_get_clubs() TO authenticated;

-- ── Fix 3: admin_get_facilities — drop+recreate clears signature cache ─
DROP FUNCTION IF EXISTS admin_get_facilities();
CREATE FUNCTION admin_get_facilities()
RETURNS TABLE (
  id            uuid,
  name          text,
  address       text,
  emirate       text,
  courts_count  int,
  image_url     text,
  created_at    timestamptz,
  creator_email text,
  clubs_count   bigint
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  SELECT
    f.id,
    f.name,
    f.address,
    f.emirate,
    f.courts_count,
    f.image_url,
    f.created_at,
    au.email::text,
    COUNT(c.id)::bigint
  FROM facilities f
  LEFT JOIN auth.users au ON au.id = f.created_by
  LEFT JOIN clubs c       ON c.facility_id = f.id
  GROUP BY f.id, f.name, f.address, f.emirate, f.courts_count,
           f.image_url, f.created_at, au.email
  ORDER BY f.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_get_facilities() TO authenticated;

-- ── New: admin_create_facility — admin can add facilities directly ─────
CREATE OR REPLACE FUNCTION admin_create_facility(
  p_name         text,
  p_address      text DEFAULT NULL,
  p_emirate      text DEFAULT NULL,
  p_courts_count int  DEFAULT NULL,
  p_image_url    text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF trim(p_name) = '' THEN RAISE EXCEPTION 'Name cannot be empty'; END IF;
  INSERT INTO facilities (name, address, emirate, courts_count, image_url, created_by)
  VALUES (trim(p_name), p_address, p_emirate, p_courts_count, p_image_url, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_create_facility(text, text, text, int, text) TO authenticated;
