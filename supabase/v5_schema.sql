-- =====================================================================
-- Badmint v5 — Sessions, Activity Log, Online Status
-- Run in Supabase SQL Editor AFTER v4_schema.sql
-- =====================================================================

-- ── last_seen_at on user_profiles (online status) ──
alter table user_profiles add column if not exists last_seen_at timestamptz;

-- ── App Sessions ──
create table if not exists app_sessions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  ip_address     text,
  user_agent     text,
  logged_in_at   timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  logged_out_at  timestamptz,
  is_active      boolean not null default true
);
create index if not exists idx_sessions_user on app_sessions(user_id);
create index if not exists idx_sessions_active on app_sessions(is_active, last_active_at desc);

-- ── Activity Log (page views + actions, linked to session) ──
create table if not exists activity_log (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid references app_sessions(id) on delete cascade,
  user_id     uuid references auth.users(id) on delete cascade,
  event_type  text not null,   -- 'page_view' | 'match_created' | 'player_added' | ...
  event_data  jsonb,           -- { path: '/dashboard' } or { match_id: '...' }
  created_at  timestamptz not null default now()
);
create index if not exists idx_activity_session on activity_log(session_id, created_at desc);
create index if not exists idx_activity_user    on activity_log(user_id, created_at desc);

-- ── RLS ──
alter table app_sessions enable row level security;
alter table activity_log  enable row level security;

-- Users manage their own sessions; no cross-user reads (admin reads added later)
do $$ begin
  create policy sess_own on app_sessions for all
    using (user_id = auth.uid()) with check (user_id = auth.uid());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy act_insert on activity_log for insert
    with check (user_id = auth.uid());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy act_read on activity_log for select
    using (user_id = auth.uid());
exception when duplicate_object then null; end $$;

-- ── RPCs ──

-- Create session on login — captures IP from PostgREST request headers
create or replace function create_session(p_user_agent text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_ip text;
begin
  -- Extract real IP from PostgREST headers (Supabase passes these automatically)
  begin
    v_ip := current_setting('request.headers', true)::json->>'x-real-ip';
    if v_ip is null or v_ip = '' then
      v_ip := split_part(
        current_setting('request.headers', true)::json->>'x-forwarded-for',
        ',', 1
      );
    end if;
  exception when others then
    v_ip := null;
  end;

  insert into app_sessions(user_id, ip_address, user_agent)
  values (auth.uid(), nullif(trim(v_ip),''), coalesce(p_user_agent, 'unknown'))
  returning id into v_id;

  -- Upsert last_seen_at in user_profiles
  insert into user_profiles(user_id, last_seen_at, updated_at)
  values (auth.uid(), now(), now())
  on conflict (user_id) do update
    set last_seen_at = now(), updated_at = now();

  return v_id;
end;
$$;

-- Log a page view or action
create or replace function log_activity(
  p_session_id uuid,
  p_event_type text,
  p_event_data jsonb default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into activity_log(session_id, user_id, event_type, event_data)
  values (p_session_id, auth.uid(), p_event_type, p_event_data);

  -- Keep session heartbeat alive
  update app_sessions
    set last_active_at = now()
    where id = p_session_id and user_id = auth.uid();

  -- Update online presence
  update user_profiles
    set last_seen_at = now(), updated_at = now()
    where user_id = auth.uid();
end;
$$;

-- Close session on explicit logout
create or replace function end_session(p_session_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update app_sessions
    set logged_out_at = now(), is_active = false
    where id = p_session_id and user_id = auth.uid();
end;
$$;

-- Get club players with online status (replaces direct table query in Players.vue)
create or replace function get_club_players(p_club_id uuid)
returns table(
  id           uuid,
  display_name text,
  elo          numeric,
  is_active    boolean,
  user_id      uuid,
  last_seen_at timestamptz,
  online_status text   -- 'online' | 'recent' | 'offline'
) language sql stable security definer set search_path = public as $$
  select
    p.id, p.display_name, p.elo, p.is_active, p.user_id,
    up.last_seen_at,
    case
      when up.last_seen_at >= now() - interval '10 minutes' then 'online'
      when up.last_seen_at >= now() - interval '1 month'    then 'recent'
      else                                                       'offline'
    end as online_status
  from players p
  left join user_profiles up on up.user_id = p.user_id
  where p.club_id = p_club_id
  order by p.is_active desc, p.elo desc;
$$;

grant execute on function create_session(text)                   to authenticated;
grant execute on function log_activity(uuid, text, jsonb)        to authenticated;
grant execute on function end_session(uuid)                      to authenticated;
grant execute on function get_club_players(uuid)                 to authenticated;
