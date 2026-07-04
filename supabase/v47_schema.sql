-- =====================================================================
-- Badminton 360 v47 — Club logo
-- Run in Supabase SQL Editor (after v46_schema.sql)
--
-- Club managers/owners can upload a club image. The image is compressed
-- client-side (src/lib/imageCompress.js — square JPEG data-URI, ≤ ~60 KB)
-- and stored directly in the DB as a data URI, same pattern as
-- user_profiles.avatar_url (no Supabase Storage bucket needed).
-- =====================================================================

-- ── 1. Column ─────────────────────────────────────────────────────────
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS logo_url text;

-- ── 2. update_club_logo RPC (manager/owner only) ─────────────────────
CREATE OR REPLACE FUNCTION update_club_logo(p_club_id uuid, p_logo text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id
      AND user_id = auth.uid()
      AND role IN ('owner','manager')
  ) THEN
    RAISE EXCEPTION 'Only club managers or owners can change the club logo';
  END IF;

  -- NULL clears the logo. Otherwise require a compressed data-URI within
  -- a hard size budget so an oversized payload can never bloat the table
  -- (client compresses to ≤ ~60 KB; 100 000 chars ≈ 73 KB binary).
  IF p_logo IS NOT NULL THEN
    IF p_logo NOT LIKE 'data:image/%' THEN
      RAISE EXCEPTION 'Logo must be an image data URI';
    END IF;
    IF length(p_logo) > 100000 THEN
      RAISE EXCEPTION 'Logo image is too large — please pick a smaller image';
    END IF;
  END IF;

  UPDATE clubs SET logo_url = p_logo WHERE id = p_club_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_club_logo(uuid, text) TO authenticated;

-- ── 3. get_public_clubs: append description, created_at, logo_url ────
-- Return type changes, so DROP first (CREATE OR REPLACE cannot alter the
-- OUT column list). New columns are appended LAST — same lesson as v45.
-- description/created_at were already read by ClubProfile.vue but never
-- actually returned by this RPC; this fixes that gap too.
DROP FUNCTION IF EXISTS get_public_clubs();

CREATE OR REPLACE FUNCTION get_public_clubs()
RETURNS TABLE(
  id uuid, name text, member_count bigint, emirates text,
  facility_name text, facility_address text, maps_url text,
  matches_30d bigint, active_30d bigint, club_score numeric,
  last_played date, club_rank bigint,
  description text, created_at timestamptz, logo_url text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    cr.club_id, cr.name, cr.total_members::bigint, cr.emirates,
    cr.facility_name, cr.facility_address, cr.maps_url,
    cr.matches_30d::bigint, cr.active_30d::bigint, cr.club_score,
    cr.last_played, cr.club_rank,
    cr.description, c.created_at, c.logo_url
  FROM v_club_rankings cr
  JOIN clubs c ON c.id = cr.club_id
  ORDER BY cr.club_rank;
$$;

GRANT EXECUTE ON FUNCTION get_public_clubs() TO authenticated, anon;
