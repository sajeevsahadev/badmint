-- v84_hide_closed_clubs_from_listings
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Closed clubs must not appear in ANY browse/listing (Explore, Join, Home,
-- onboarding). get_public_clubs now excludes them. ClubProfile fetches a
-- single club by id via the new get_club_ranking (no policy filter) so members
-- can still view their own closed club's profile.

CREATE OR REPLACE FUNCTION public.get_public_clubs(p_country_code text DEFAULT NULL::text)
RETURNS TABLE(id uuid, name text, member_count bigint, emirates text,
              facility_name text, facility_address text, maps_url text,
              matches_30d bigint, active_30d bigint, club_score numeric,
              last_played date, club_rank bigint, description text,
              created_at timestamptz, logo_url text, currency text,
              country_code text, is_public boolean, join_policy text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT
    cr.club_id, cr.name, cr.total_members::bigint, cr.emirates,
    cr.facility_name, cr.facility_address, cr.maps_url,
    cr.matches_30d::bigint, cr.active_30d::bigint, cr.club_score,
    cr.last_played, cr.club_rank,
    cr.description, c.created_at, c.logo_url, c.currency,
    c.country_code, c.is_public, c.join_policy
  FROM v_club_rankings cr
  JOIN clubs c ON c.id = cr.club_id
  WHERE (p_country_code IS NULL OR c.country_code = upper(trim(p_country_code)))
    AND c.is_public = true              -- legacy visibility flag
    AND c.join_policy <> 'closed'        -- closed = invite-only, never listed
  ORDER BY cr.club_rank;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_clubs(text) TO anon, authenticated;

-- Single-club ranking row (same shape) regardless of join policy — for the
-- club profile page, which must render even for closed clubs (their members
-- reach it directly by id).
CREATE OR REPLACE FUNCTION public.get_club_ranking(p_club_id uuid)
RETURNS TABLE(id uuid, name text, member_count bigint, emirates text,
              facility_name text, facility_address text, maps_url text,
              matches_30d bigint, active_30d bigint, club_score numeric,
              last_played date, club_rank bigint, description text,
              created_at timestamptz, logo_url text, currency text,
              country_code text, is_public boolean, join_policy text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT
    cr.club_id, cr.name, cr.total_members::bigint, cr.emirates,
    cr.facility_name, cr.facility_address, cr.maps_url,
    cr.matches_30d::bigint, cr.active_30d::bigint, cr.club_score,
    cr.last_played, cr.club_rank,
    cr.description, c.created_at, c.logo_url, c.currency,
    c.country_code, c.is_public, c.join_policy
  FROM v_club_rankings cr
  JOIN clubs c ON c.id = cr.club_id
  WHERE cr.club_id = p_club_id;
$$;
GRANT EXECUTE ON FUNCTION public.get_club_ranking(uuid) TO anon, authenticated;;
