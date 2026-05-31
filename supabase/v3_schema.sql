-- =====================================================================
-- Badmint v3 — Additive migration
-- Run in Supabase SQL Editor AFTER v2_schema.sql
-- =====================================================================

-- ── Extend user_profiles with onboarding fields ──
alter table user_profiles add column if not exists full_name text;
alter table user_profiles add column if not exists emirate   text
  check (emirate in ('Abu Dhabi','Dubai','Sharjah','Ajman',
                     'Umm Al Quwain','Ras Al Khaimah','Fujairah'));
alter table user_profiles add column if not exists country   text not null default 'UAE';

-- ── Updated upsert_profile — includes new fields ──
create or replace function upsert_profile(
  p_nickname  text,
  p_full_name text    default null,
  p_phone     text    default null,
  p_bio       text    default null,
  p_emirate   text    default null,
  p_country   text    default 'UAE'
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into user_profiles(user_id, nickname, full_name, phone, bio, emirate, country, updated_at)
    values (auth.uid(), p_nickname, p_full_name, p_phone, p_bio, p_emirate, p_country, now())
    on conflict (user_id) do update set
      nickname   = excluded.nickname,
      full_name  = coalesce(excluded.full_name,  user_profiles.full_name),
      phone      = coalesce(excluded.phone,      user_profiles.phone),
      bio        = coalesce(excluded.bio,        user_profiles.bio),
      emirate    = coalesce(excluded.emirate,    user_profiles.emirate),
      country    = coalesce(excluded.country,    user_profiles.country),
      updated_at = now();
end;
$$;

grant execute on function upsert_profile(text, text, text, text, text, text) to authenticated;
