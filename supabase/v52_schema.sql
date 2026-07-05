-- =====================================================================
-- Badminton 360 v52 — Per-club currency
-- Run in Supabase SQL Editor (after v51_schema.sql).
--
-- Money in Split Pay / Wallet / tournament fees was hard-coded to AED.
-- Clubs outside the UAE (e.g. an India-based club) need their own
-- currency. Each club now stores a 3-letter ISO 4217 currency code; the
-- app suggests it from the creator's IP-detected country at creation and
-- lets managers change it later.
--
-- Fix 1: clubs.currency column (default 'AED', kept for existing clubs).
-- Fix 2: create_club gains an optional p_currency param (validated).
-- Fix 3: set_club_currency() RPC — managers/owners change it afterwards.
-- (useClub reads clubs.currency via its members-can-read-their-clubs RLS
--  select, so no view change is needed for the app to see it.)
-- =====================================================================

-- ── Fix 1: currency column ───────────────────────────────────────────
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'AED';

-- ── helper: validate a 3-letter uppercase ISO code ───────────────────
-- Normalises to upper, defaults blank/invalid to 'AED'.
CREATE OR REPLACE FUNCTION norm_currency(p text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE
    WHEN p IS NOT NULL AND upper(trim(p)) ~ '^[A-Z]{3}$' THEN upper(trim(p))
    ELSE 'AED'
  END;
$$;

-- ── Fix 2: create_club with optional currency ───────────────────────
-- Drop the older single-arg overload (v51). Keeping both would make the
-- 1-arg PostgREST call (OnboardingWizard: rpc('create_club', {p_name}))
-- ambiguous — PostgREST can't choose between create_club(text) and
-- create_club(text, text DEFAULT). One function with a default handles both.
DROP FUNCTION IF EXISTS create_club(text);

CREATE OR REPLACE FUNCTION create_club(p_name text, p_currency text DEFAULT 'AED')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id   uuid;
  v_name text;
BEGIN
  INSERT INTO clubs(name, created_by, currency)
    VALUES (p_name, auth.uid(), norm_currency(p_currency))
    RETURNING id INTO v_id;
  INSERT INTO club_members(club_id, user_id, role) VALUES (v_id, auth.uid(), 'owner');
  INSERT INTO ranking_config(club_id) VALUES (v_id);

  -- Roster row for the creator (v51 invariant: every member is a player)
  SELECT COALESCE(nickname, full_name) INTO v_name
  FROM user_profiles WHERE user_id = auth.uid();

  INSERT INTO players(club_id, user_id, display_name)
  VALUES (v_id, auth.uid(), COALESCE(NULLIF(trim(v_name), ''), 'Player'));

  RETURN v_id;
END;
$$;

-- Keep the single-arg signature working (defaults to AED) for any old caller.
GRANT EXECUTE ON FUNCTION create_club(text, text) TO authenticated;

-- ── Fix 3: set_club_currency (manager/owner only) ───────────────────
CREATE OR REPLACE FUNCTION set_club_currency(p_club_id uuid, p_currency text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_manager(p_club_id) THEN
    RAISE EXCEPTION 'Only club managers or owners can change the currency';
  END IF;
  UPDATE clubs SET currency = norm_currency(p_currency) WHERE id = p_club_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_club_currency(uuid, text) TO authenticated;

-- ── Also surface currency in get_public_clubs (append LAST) ──────────
DROP FUNCTION IF EXISTS get_public_clubs();
CREATE OR REPLACE FUNCTION get_public_clubs()
RETURNS TABLE(
  id uuid, name text, member_count bigint, emirates text,
  facility_name text, facility_address text, maps_url text,
  matches_30d bigint, active_30d bigint, club_score numeric,
  last_played date, club_rank bigint,
  description text, created_at timestamptz, logo_url text, currency text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    cr.club_id, cr.name, cr.total_members::bigint, cr.emirates,
    cr.facility_name, cr.facility_address, cr.maps_url,
    cr.matches_30d::bigint, cr.active_30d::bigint, cr.club_score,
    cr.last_played, cr.club_rank,
    cr.description, c.created_at, c.logo_url, c.currency
  FROM v_club_rankings cr
  JOIN clubs c ON c.id = cr.club_id
  ORDER BY cr.club_rank;
$$;
GRANT EXECUTE ON FUNCTION get_public_clubs() TO authenticated, anon;
