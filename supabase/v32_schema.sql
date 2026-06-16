-- v32_schema.sql — Profile settings expansion
-- Gender field, appearance/theme preference, email + push notification
-- preferences, and a WebAuthn credentials table for the biometric app-lock.
-- Also consolidates the two upsert_profile() overloads (v2 3-param +
-- v3 6-param) into a single 7-param function so the long-standing
-- "could not choose best candidate function" ambiguity is gone for good.

-- ── New profile columns ──────────────────────────────────────────────────────
alter table user_profiles add column if not exists gender text
  check (gender in ('male','female','non_binary','unspecified'));

alter table user_profiles add column if not exists theme_pref text not null default 'system'
  check (theme_pref in ('light','dark','system'));

alter table user_profiles add column if not exists email_prefs jsonb not null default
  '{"invites":true,"match_recorded":false,"weekly_digest":true,"payment_reminders":true,"news":true}'::jsonb;

alter table user_profiles add column if not exists push_prefs jsonb not null default
  '{"invites":true,"match_recorded":true,"schedule_polls":true,"payment_reminders":true}'::jsonb;

-- ── Consolidated upsert_profile (replaces v2 3-param + v3 6-param overloads) ──
drop function if exists upsert_profile(text, text, text);
drop function if exists upsert_profile(text, text, text, text, text, text);

create or replace function upsert_profile(
  p_nickname  text,
  p_full_name text default null,
  p_phone     text default null,
  p_bio       text default null,
  p_emirate   text default null,
  p_country   text default null,
  p_gender    text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_gender is not null and p_gender not in ('male','female','non_binary','unspecified') then
    raise exception 'Invalid gender value';
  end if;

  insert into user_profiles(user_id, nickname, full_name, phone, bio, emirate, country, gender, updated_at)
    values (auth.uid(), p_nickname, p_full_name, p_phone, p_bio, p_emirate, p_country, p_gender, now())
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
grant execute on function upsert_profile(text, text, text, text, text, text, text) to authenticated;

-- ── Appearance preference ────────────────────────────────────────────────────
create or replace function update_theme_pref(p_theme text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_theme not in ('light','dark','system') then
    raise exception 'Invalid theme value';
  end if;
  insert into user_profiles(user_id, theme_pref, updated_at)
    values (auth.uid(), p_theme, now())
    on conflict (user_id) do update set
      theme_pref = excluded.theme_pref,
      updated_at = now();
end;
$$;
grant execute on function update_theme_pref(text) to authenticated;

-- ── Email / push notification preferences ────────────────────────────────────
create or replace function update_notification_prefs(
  p_email_prefs jsonb default null,
  p_push_prefs  jsonb default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into user_profiles(user_id, email_prefs, push_prefs, updated_at)
    values (
      auth.uid(),
      coalesce(p_email_prefs, '{"invites":true,"match_recorded":false,"weekly_digest":true,"payment_reminders":true,"news":true}'::jsonb),
      coalesce(p_push_prefs,  '{"invites":true,"match_recorded":true,"schedule_polls":true,"payment_reminders":true}'::jsonb),
      now()
    )
  on conflict (user_id) do update set
    email_prefs = coalesce(p_email_prefs, user_profiles.email_prefs),
    push_prefs  = coalesce(p_push_prefs,  user_profiles.push_prefs),
    updated_at  = now();
end;
$$;
grant execute on function update_notification_prefs(jsonb, jsonb) to authenticated;

-- ── WebAuthn credentials (biometric app-lock) ────────────────────────────────
-- Stores only the credential ID + a device label per registered platform
-- authenticator (Face ID / Touch ID / Windows Hello / Android fingerprint).
-- No public key or signature verification happens server-side: this gates
-- re-entry to an ALREADY-valid Supabase session on THIS device only — it
-- never substitutes for Google sign-in. A successful
-- navigator.credentials.get() resolving is proof enough for that threat
-- model (re-locking an open session, not authenticating a new one).
create table if not exists webauthn_credentials (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  credential_id text not null unique,
  device_label  text,
  created_at    timestamptz not null default now(),
  last_used_at  timestamptz
);

alter table webauthn_credentials enable row level security;

do $$ begin
  create policy wc_own_all on webauthn_credentials for all
    using (user_id = auth.uid()) with check (user_id = auth.uid());
exception when duplicate_object then null; end $$;
