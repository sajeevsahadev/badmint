-- =====================================================================
-- Badmint v15 — App-level Roles, Admin Panel, Tournament Permission Guard
-- Run in Supabase SQL Editor after v14_schema.sql
-- =====================================================================

-- ── app_roles table ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app_roles (
  user_id           uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role              text NOT NULL CHECK (role IN ('app_admin','tournament_director','facility_manager')),
  tournament_quota  int  DEFAULT NULL,   -- NULL = unlimited; 0 = none; N = max total
  facility_id       uuid REFERENCES facilities(id) ON DELETE SET NULL,
  granted_by        uuid REFERENCES auth.users(id),
  granted_at        timestamptz NOT NULL DEFAULT now(),
  notes             text,
  PRIMARY KEY (user_id, role)
);

CREATE INDEX IF NOT EXISTS idx_app_roles_user  ON app_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_app_roles_role  ON app_roles(role);

ALTER TABLE app_roles ENABLE ROW LEVEL SECURITY;

-- Users can read their OWN roles (needed for in-app role checks)
CREATE POLICY "app_roles_read_own"
  ON app_roles FOR SELECT USING (user_id = auth.uid());

-- All writes via SECURITY DEFINER RPCs only (no direct insert/update/delete)

-- ── Helper: is_app_admin() ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_app_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM app_roles
    WHERE user_id = auth.uid() AND role = 'app_admin'
  )
$$;

GRANT EXECUTE ON FUNCTION is_app_admin() TO authenticated;

-- ── Helper: is_tournament_director() ─────────────────────────────────
CREATE OR REPLACE FUNCTION is_tournament_director()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM app_roles
    WHERE user_id = auth.uid() AND role = 'tournament_director'
  )
$$;

GRANT EXECUTE ON FUNCTION is_tournament_director() TO authenticated;

-- ── Helper: get_my_roles() ────────────────────────────────────────────
-- Returns all roles for the calling user (used on app load)
CREATE OR REPLACE FUNCTION get_my_roles()
RETURNS TABLE (role text, tournament_quota int, facility_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role, tournament_quota, facility_id
  FROM app_roles
  WHERE user_id = auth.uid()
$$;

GRANT EXECUTE ON FUNCTION get_my_roles() TO authenticated;

-- ── Updated create_tournament (replaces v14 version) ─────────────────
-- Now guards: must be app_admin OR tournament_director with remaining quota
CREATE OR REPLACE FUNCTION create_tournament(
  p_club_id         uuid,
  p_name            text,
  p_format          text DEFAULT 'single_elimination',
  p_max_teams       int  DEFAULT 16,
  p_description     text DEFAULT NULL,
  p_entry_fee       numeric DEFAULT NULL,
  p_prize_info      text DEFAULT NULL,
  p_venue           text DEFAULT NULL,
  p_venue_address   text DEFAULT NULL,
  p_emirate         text DEFAULT NULL,
  p_registration_end date DEFAULT NULL,
  p_start_date      date DEFAULT NULL,
  p_end_date        date DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id      uuid;
  v_created int;
  v_quota   int;
BEGIN
  -- Permission check
  IF NOT is_app_admin() THEN
    -- Check tournament_director role + quota
    SELECT tournament_quota
    INTO v_quota
    FROM app_roles
    WHERE user_id = auth.uid() AND role = 'tournament_director';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Tournament creation requires director permission. Contact the platform admin at sajeevsahadev@gmail.com to request access.';
    END IF;

    IF v_quota IS NOT NULL THEN
      -- Count non-cancelled tournaments already created
      SELECT COUNT(*) INTO v_created
      FROM tournaments
      WHERE created_by = auth.uid() AND status <> 'cancelled';

      IF v_created >= v_quota THEN
        RAISE EXCEPTION 'You have used your tournament creation quota (% of % allowed). Contact the admin to increase your quota.',
          v_created, v_quota;
      END IF;
    END IF;
  END IF;

  IF p_format NOT IN ('single_elimination','round_robin') THEN
    RAISE EXCEPTION 'Invalid format';
  END IF;

  INSERT INTO tournaments (
    club_id, name, format, max_teams, description,
    entry_fee, prize_info, venue, venue_address, emirate,
    registration_end, start_date, end_date, created_by
  ) VALUES (
    p_club_id, p_name, p_format, p_max_teams, p_description,
    p_entry_fee, p_prize_info, p_venue, p_venue_address, p_emirate,
    p_registration_end, p_start_date, p_end_date, auth.uid()
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_tournament(uuid,text,text,int,text,numeric,text,text,text,text,date,date,date) TO authenticated;

-- ── Admin: grant_role ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION grant_role(
  p_user_id          uuid,
  p_role             text,
  p_tournament_quota int  DEFAULT NULL,
  p_facility_id      uuid DEFAULT NULL,
  p_notes            text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN
    RAISE EXCEPTION 'Only app admins can grant roles';
  END IF;

  IF p_role NOT IN ('app_admin','tournament_director','facility_manager') THEN
    RAISE EXCEPTION 'Invalid role: %', p_role;
  END IF;

  INSERT INTO app_roles (user_id, role, tournament_quota, facility_id, granted_by, notes)
  VALUES (p_user_id, p_role, p_tournament_quota, p_facility_id, auth.uid(), p_notes)
  ON CONFLICT (user_id, role) DO UPDATE
    SET tournament_quota = COALESCE(EXCLUDED.tournament_quota, app_roles.tournament_quota),
        facility_id      = COALESCE(EXCLUDED.facility_id,      app_roles.facility_id),
        notes            = COALESCE(EXCLUDED.notes,            app_roles.notes),
        granted_by       = EXCLUDED.granted_by,
        granted_at       = now();
END;
$$;

GRANT EXECUTE ON FUNCTION grant_role(uuid,text,int,uuid,text) TO authenticated;

-- ── Admin: revoke_role ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION revoke_role(p_user_id uuid, p_role text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Only app admins can revoke roles'; END IF;
  DELETE FROM app_roles WHERE user_id = p_user_id AND role = p_role;
END;
$$;

GRANT EXECUTE ON FUNCTION revoke_role(uuid,text) TO authenticated;

-- ── Admin: update_tournament_quota ────────────────────────────────────
CREATE OR REPLACE FUNCTION update_tournament_quota(p_user_id uuid, p_quota int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Only app admins can update quotas'; END IF;
  UPDATE app_roles SET tournament_quota = p_quota
  WHERE user_id = p_user_id AND role = 'tournament_director';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User does not have tournament_director role';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION update_tournament_quota(uuid,int) TO authenticated;

-- ── Admin: get_all_users ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_all_users(p_search text DEFAULT NULL)
RETURNS TABLE (
  user_id       uuid,
  email         text,
  full_name     text,
  nickname      text,
  last_sign_in  timestamptz,
  created_at    timestamptz,
  roles         jsonb,
  tournaments_created bigint
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  RETURN QUERY
  SELECT
    u.id                                                                       AS user_id,
    u.email                                                                    AS email,
    COALESCE(up.full_name, u.raw_user_meta_data->>'full_name')                AS full_name,
    up.nickname                                                                AS nickname,
    u.last_sign_in_at                                                         AS last_sign_in,
    u.created_at                                                              AS created_at,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'role',             ar.role,
        'tournament_quota', ar.tournament_quota,
        'facility_id',      ar.facility_id,
        'granted_at',       ar.granted_at,
        'notes',            ar.notes
      ) ORDER BY ar.granted_at)
      FROM app_roles ar WHERE ar.user_id = u.id
    ), '[]'::jsonb)                                                            AS roles,
    (SELECT COUNT(*) FROM tournaments t WHERE t.created_by = u.id)           AS tournaments_created
  FROM auth.users u
  LEFT JOIN user_profiles up ON up.user_id = u.id
  WHERE p_search IS NULL
     OR u.email ILIKE '%' || p_search || '%'
     OR up.nickname ILIKE '%' || p_search || '%'
     OR up.full_name ILIKE '%' || p_search || '%'
     OR (u.raw_user_meta_data->>'full_name') ILIKE '%' || p_search || '%'
  ORDER BY u.created_at DESC
  LIMIT 100;
END;
$$;

GRANT EXECUTE ON FUNCTION get_all_users(text) TO authenticated;

-- ── Admin: get_platform_stats ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_platform_stats()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;

  RETURN jsonb_build_object(
    'total_users',       (SELECT COUNT(*) FROM auth.users),
    'total_clubs',       (SELECT COUNT(*) FROM clubs),
    'total_members',     (SELECT COUNT(*) FROM club_members),
    'total_matches',     (SELECT COUNT(*) FROM matches),
    'total_tournaments', (SELECT COUNT(*) FROM tournaments),
    'live_tournaments',  (SELECT COUNT(*) FROM tournaments WHERE status = 'live'),
    'open_tournaments',  (SELECT COUNT(*) FROM tournaments WHERE status = 'registration_open'),
    'total_facilities',  (SELECT COUNT(*) FROM facilities),
    'directors',         (SELECT COUNT(*) FROM app_roles WHERE role = 'tournament_director'),
    'facility_managers', (SELECT COUNT(*) FROM app_roles WHERE role = 'facility_manager'),
    'clubs_by_emirate',  (
      SELECT jsonb_object_agg(COALESCE(emirates,'Unknown'), cnt)
      FROM (SELECT emirates, COUNT(*) AS cnt FROM clubs GROUP BY emirates) x
    ),
    'matches_last_30d',  (
      SELECT COUNT(*) FROM matches WHERE played_on >= current_date - 30
    ),
    'new_users_last_7d', (
      SELECT COUNT(*) FROM auth.users
      WHERE created_at >= now() - interval '7 days'
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_platform_stats() TO authenticated;

-- =====================================================================
-- SETUP: Make yourself super admin
-- Replace the email below with yours and run ONCE:
-- =====================================================================
-- INSERT INTO app_roles (user_id, role, granted_by, notes)
-- SELECT id, 'app_admin', id, 'Platform founder'
-- FROM auth.users
-- WHERE email = 'sajeevsahadev@gmail.com'
-- ON CONFLICT DO NOTHING;
-- =====================================================================
