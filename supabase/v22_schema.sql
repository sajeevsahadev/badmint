-- =====================================================================
-- Badmint v22 — Super Admin: clubs, facilities & tournaments management
-- Run once in Supabase SQL Editor (safe re-run; CREATE OR REPLACE)
-- =====================================================================

-- ── STEP 1: Grant yourself super admin (run once, then you're done) ──
INSERT INTO app_roles (user_id, role, granted_by, notes)
SELECT id, 'app_admin', id, 'Platform founder'
FROM auth.users
WHERE email = 'sajeevsahadev@gmail.com'
ON CONFLICT DO NOTHING;

-- ── admin_get_clubs: all clubs with owner info ────────────────────────
-- Uses clubs table directly (not v_club_rankings) so zero-activity
-- clubs (no matches yet) are also shown.
CREATE OR REPLACE FUNCTION admin_get_clubs()
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
  SELECT
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
  LEFT JOIN club_members cm   ON cm.club_id  = c.id AND cm.role = 'owner'
  LEFT JOIN auth.users au     ON au.id        = cm.user_id
  LEFT JOIN user_profiles up  ON up.user_id   = cm.user_id
  ORDER BY COALESCE(cr.club_rank, 999999), c.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_get_clubs() TO authenticated;

-- ── admin_rename_club: rename any club (bypasses ownership check) ─────
CREATE OR REPLACE FUNCTION admin_rename_club(p_club_id uuid, p_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF trim(p_name) = '' THEN RAISE EXCEPTION 'Name cannot be empty'; END IF;
  UPDATE clubs SET name = trim(p_name) WHERE id = p_club_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_rename_club(uuid, text) TO authenticated;

-- ── admin_get_facilities: all facilities with creator + linked clubs ──
CREATE OR REPLACE FUNCTION admin_get_facilities()
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

-- ── admin_update_facility: edit any facility details ──────────────────
CREATE OR REPLACE FUNCTION admin_update_facility(
  p_id           uuid,
  p_name         text,
  p_address      text DEFAULT NULL,
  p_emirate      text DEFAULT NULL,
  p_courts_count int  DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF trim(p_name) = '' THEN RAISE EXCEPTION 'Name cannot be empty'; END IF;
  UPDATE facilities SET
    name         = trim(p_name),
    address      = p_address,
    emirate      = p_emirate,
    courts_count = p_courts_count
  WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_update_facility(uuid, text, text, text, int) TO authenticated;

-- ── admin_delete_facility: delete facility + cascade unlink ──────────
CREATE OR REPLACE FUNCTION admin_delete_facility(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  -- Unlink clubs (no ON DELETE CASCADE on clubs.facility_id)
  UPDATE clubs SET facility_id = NULL WHERE facility_id = p_id;
  DELETE FROM facility_bookings WHERE facility_id = p_id;
  DELETE FROM facility_schedule  WHERE facility_id = p_id;
  DELETE FROM facilities         WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_delete_facility(uuid) TO authenticated;

-- ── admin_get_tournaments: all tournaments with club + creator info ────
CREATE OR REPLACE FUNCTION admin_get_tournaments()
RETURNS TABLE (
  id                 uuid,
  name               text,
  club_id            uuid,
  club_name          text,
  status             text,
  format             text,
  max_teams          int,
  start_date         date,
  end_date           date,
  created_at         timestamptz,
  creator_email      text,
  registration_count bigint
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  SELECT
    t.id,
    t.name,
    t.club_id,
    c.name::text,
    t.status,
    t.format,
    t.max_teams,
    t.start_date,
    t.end_date,
    t.created_at,
    au.email::text,
    COUNT(tr.id)::bigint
  FROM tournaments t
  LEFT JOIN clubs c                    ON c.id  = t.club_id
  LEFT JOIN auth.users au              ON au.id = t.created_by
  LEFT JOIN tournament_registrations tr ON tr.tournament_id = t.id
  GROUP BY t.id, t.name, t.club_id, c.name, t.status, t.format,
           t.max_teams, t.start_date, t.end_date, t.created_at, au.email
  ORDER BY t.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_get_tournaments() TO authenticated;
