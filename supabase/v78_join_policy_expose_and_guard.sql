-- v78_join_policy_expose_and_guard
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- v78: block self-join on closed clubs; expose join_policy to the join UI

-- ── request_join: reject closed clubs (manual invite only) ──
CREATE OR REPLACE FUNCTION public.request_join(p_club_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
declare
  v_email  text;
  v_name   text;
  v_total  integer;
  v_policy text;
begin
  SELECT join_policy INTO v_policy FROM clubs WHERE id = p_club_id;
  IF v_policy = 'closed' THEN
    RAISE EXCEPTION 'This club is closed. Ask a manager to send you an invite.';
  END IF;

  -- Enforce 5-club limit (memberships + pending requests)
  select
    (select count(*) from club_members  where user_id = auth.uid()) +
    (select count(*) from join_requests where user_id = auth.uid() and status = 'pending')
  into v_total;

  if v_total >= 5 then
    raise exception 'You have reached the maximum of 5 clubs. Leave a club or revoke a pending request before joining another.';
  end if;

  select
    u.email,
    coalesce(
      u.raw_user_meta_data->>'full_name',
      u.raw_user_meta_data->>'name',
      split_part(u.email, '@', 1)
    )
  into v_email, v_name
  from auth.users u where u.id = auth.uid();

  insert into join_requests(club_id, user_id, user_email, user_name)
    values (p_club_id, auth.uid(), v_email, v_name)
    on conflict (club_id, user_id) do update
      set status = 'pending', created_at = now()
      where join_requests.status = 'rejected';
end;
$$;

-- ── Expose join_policy from the public club lookups ──
DROP FUNCTION IF EXISTS public.get_public_club_by_id(uuid);
CREATE FUNCTION public.get_public_club_by_id(p_club_id uuid)
RETURNS TABLE(id uuid, name text, member_count bigint, emirates text,
              facility_name text, facility_address text, logo_url text,
              is_public boolean, country_code text, join_policy text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT
    cr.club_id, cr.name, cr.total_members::bigint, cr.emirates,
    cr.facility_name, cr.facility_address,
    c.logo_url, c.is_public, c.country_code, c.join_policy
  FROM v_club_rankings cr
  JOIN clubs c ON c.id = cr.club_id
  WHERE cr.club_id = p_club_id;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_club_by_id(uuid) TO anon, authenticated;

DROP FUNCTION IF EXISTS public.get_public_clubs(text);
CREATE FUNCTION public.get_public_clubs(p_country_code text DEFAULT NULL::text)
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
  WHERE p_country_code IS NULL OR c.country_code = upper(trim(p_country_code))
  ORDER BY c.is_public DESC, cr.club_rank;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_clubs(text) TO anon, authenticated;;
