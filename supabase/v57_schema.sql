-- =====================================================================
-- Badminton 360 v57 — Club discoverability, direct join links, country filter
-- Run in Supabase SQL Editor. (Applied to prod.)
--
-- Implements:
--  - clubs.country_code (ISO-2) + clubs.is_public (discoverability toggle)
--  - create_club captures country_code (mirrors the currency-suggestion
--    pattern: IP-detected at creation, editable later)
--  - set_club_visibility() — manager toggles public/closed
--  - get_public_clubs(p_country_code) — server-side country filter (NOT
--    client-side — fetching every club worldwide to filter in JS does not
--    scale as the club count grows internationally), open clubs sorted
--    before closed ones, country_code/is_public exposed
--  - get_club_countries() — distinct country list for the filter dropdown
--  - get_public_club_by_id() — lightweight single-club fetch for the new
--    direct "/join/:clubId" shareable link (avoids pulling the full club
--    list just to find one row)
--
-- Design note on is_public: this is a DISCOVERABILITY toggle, not an access
-- control. It hides the "Request to Join" button in public search/browse
-- for closed clubs. It does NOT and architecturally cannot cryptographically
-- block request_join() for someone who already has the club_id (e.g. from
-- the admin's shared join link, or the club's own public /club/:id profile
-- page, which is public regardless of this flag). request_join() already
-- requires manager approval before membership either way, so this remains
-- safe; it is intentionally not a secret-invite-code system, matching what
-- was actually asked for ("indicate it's a closed club" — discoverability
-- language, not an access-control request).
-- =====================================================================

-- ── 1. New columns ────────────────────────────────────────────────────
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS country_code text NOT NULL DEFAULT 'AE';
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT true;
CREATE INDEX IF NOT EXISTS idx_clubs_country_code ON clubs(country_code);

-- ── helper: validate a 2-letter uppercase ISO country code ───────────
CREATE OR REPLACE FUNCTION norm_country_code(p text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE
    WHEN p IS NOT NULL AND upper(trim(p)) ~ '^[A-Z]{2}$' THEN upper(trim(p))
    ELSE 'AE'
  END;
$$;

-- ── 2. create_club: also capture country_code ────────────────────────
DROP FUNCTION IF EXISTS create_club(text, text);

CREATE OR REPLACE FUNCTION create_club(
  p_name text,
  p_currency text DEFAULT 'AED',
  p_country_code text DEFAULT 'AE'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id   uuid;
  v_name text;
BEGIN
  INSERT INTO clubs(name, created_by, currency, country_code)
    VALUES (p_name, auth.uid(), norm_currency(p_currency), norm_country_code(p_country_code))
    RETURNING id INTO v_id;
  INSERT INTO club_members(club_id, user_id, role) VALUES (v_id, auth.uid(), 'owner');
  INSERT INTO ranking_config(club_id) VALUES (v_id);

  SELECT COALESCE(nickname, full_name) INTO v_name
  FROM user_profiles WHERE user_id = auth.uid();

  INSERT INTO players(club_id, user_id, display_name)
  VALUES (v_id, auth.uid(), COALESCE(NULLIF(trim(v_name), ''), 'Player'));

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_club(text, text, text) TO authenticated;

-- ── 3. set_club_visibility — manager/owner toggles public vs closed ──
CREATE OR REPLACE FUNCTION set_club_visibility(p_club_id uuid, p_is_public boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_manager(p_club_id) THEN
    RAISE EXCEPTION 'Only club managers or owners can change club visibility';
  END IF;
  UPDATE clubs SET is_public = p_is_public WHERE id = p_club_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_club_visibility(uuid, boolean) TO authenticated;

-- ── 4. set_club_country — manager/owner corrects the country ─────────
CREATE OR REPLACE FUNCTION set_club_country(p_club_id uuid, p_country_code text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_manager(p_club_id) THEN
    RAISE EXCEPTION 'Only club managers or owners can change the club country';
  END IF;
  UPDATE clubs SET country_code = norm_country_code(p_country_code) WHERE id = p_club_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_club_country(uuid, text) TO authenticated;

-- ── 5. get_public_clubs: country filter (server-side), open-first sort ─
DROP FUNCTION IF EXISTS get_public_clubs();

CREATE OR REPLACE FUNCTION get_public_clubs(p_country_code text DEFAULT NULL)
RETURNS TABLE(
  id uuid, name text, member_count bigint, emirates text,
  facility_name text, facility_address text, maps_url text,
  matches_30d bigint, active_30d bigint, club_score numeric,
  last_played date, club_rank bigint,
  description text, created_at timestamptz, logo_url text, currency text,
  country_code text, is_public boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    cr.club_id, cr.name, cr.total_members::bigint, cr.emirates,
    cr.facility_name, cr.facility_address, cr.maps_url,
    cr.matches_30d::bigint, cr.active_30d::bigint, cr.club_score,
    cr.last_played, cr.club_rank,
    cr.description, c.created_at, c.logo_url, c.currency,
    c.country_code, c.is_public
  FROM v_club_rankings cr
  JOIN clubs c ON c.id = cr.club_id
  WHERE p_country_code IS NULL OR c.country_code = upper(trim(p_country_code))
  ORDER BY c.is_public DESC, cr.club_rank;
$$;

GRANT EXECUTE ON FUNCTION get_public_clubs(text) TO authenticated, anon;

-- ── 6. get_club_countries — distinct country list for the filter ─────
CREATE OR REPLACE FUNCTION get_club_countries()
RETURNS TABLE(country_code text, club_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT country_code, count(*)::bigint
  FROM clubs
  GROUP BY country_code
  ORDER BY country_code;
$$;

GRANT EXECUTE ON FUNCTION get_club_countries() TO authenticated, anon;

-- ── 7. get_public_club_by_id — lightweight single-club fetch, powers
--      the new direct "/join/:clubId" shareable link without pulling the
--      full worldwide club list client-side ──────────────────────────
CREATE OR REPLACE FUNCTION get_public_club_by_id(p_club_id uuid)
RETURNS TABLE(
  id uuid, name text, member_count bigint, emirates text,
  facility_name text, facility_address text,
  logo_url text, is_public boolean, country_code text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    cr.club_id, cr.name, cr.total_members::bigint, cr.emirates,
    cr.facility_name, cr.facility_address,
    c.logo_url, c.is_public, c.country_code
  FROM v_club_rankings cr
  JOIN clubs c ON c.id = cr.club_id
  WHERE cr.club_id = p_club_id;
$$;

GRANT EXECUTE ON FUNCTION get_public_club_by_id(uuid) TO authenticated, anon;
