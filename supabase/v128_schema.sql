-- =====================================================================
-- Badminton 360 v128 — upsert_profile: never INSERT NULL into country
-- Applied to prod via Supabase MCP; archived here for rebuild parity.
--
-- Bug: user_profiles.country is NOT NULL (default 'UAE'). upsert_profile's
-- INSERT wrote p_country literally, and PostgreSQL checks NOT NULL on the
-- proposed INSERT tuple BEFORE ON CONFLICT DO UPDATE can run — so a NULL
-- p_country errored ("null value in column country violates not-null") even
-- when the row already existed. This bit a first-login race: the profile-
-- completion gate loaded the profile before create_session had created the
-- row, so it sent p_country = NULL. Fix: coalesce(p_country,'UAE') on insert
-- (falls back to the column default). ON CONFLICT path unchanged.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.upsert_profile(
  p_nickname text, p_full_name text DEFAULT NULL, p_phone text DEFAULT NULL,
  p_bio text DEFAULT NULL, p_emirate text DEFAULT NULL, p_country text DEFAULT NULL,
  p_gender text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
begin
  if p_gender is not null and p_gender not in ('male','female','non_binary','unspecified') then
    raise exception 'Invalid gender value';
  end if;

  insert into user_profiles(user_id, nickname, full_name, phone, bio, emirate, country, gender, updated_at)
    values (auth.uid(), p_nickname, p_full_name, p_phone, p_bio, p_emirate, coalesce(p_country, 'UAE'), p_gender, now())
    on conflict (user_id) do update set
      nickname   = excluded.nickname,
      full_name  = coalesce(excluded.full_name,  user_profiles.full_name),
      phone      = coalesce(excluded.phone,      user_profiles.phone),
      bio        = coalesce(excluded.bio,        user_profiles.bio),
      emirate    = coalesce(excluded.emirate,    user_profiles.emirate),
      country    = coalesce(excluded.country,    user_profiles.country),
      gender     = coalesce(excluded.gender,     user_profiles.gender),
      updated_at = now();
end;
$$;
GRANT EXECUTE ON FUNCTION public.upsert_profile(text,text,text,text,text,text,text) TO authenticated;
