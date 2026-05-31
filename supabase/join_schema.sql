-- =====================================================================
-- Badmint — Additive migration: Join Requests + Club Invites
-- Run once in Supabase SQL Editor (safe to re-run; uses IF NOT EXISTS)
-- =====================================================================

-- ---------- JOIN REQUESTS (player-initiated) ----------
create table if not exists join_requests (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references clubs(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  user_email text,
  user_name  text not null default 'Player',
  status     text not null default 'pending'
             check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  unique(club_id, user_id)
);

-- ---------- CLUB INVITES (manager-initiated, token link) ----------
create table if not exists club_invites (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references clubs(id) on delete cascade,
  email       text not null,
  token       text unique not null default encode(gen_random_bytes(32), 'hex'),
  status      text not null default 'pending'
              check (status in ('pending','accepted','expired')),
  invited_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '7 days'
);

-- ---------- RLS ----------
alter table join_requests enable row level security;
alter table club_invites  enable row level security;

-- join_requests: user can insert their own; managers read/update theirs
do $$ begin
  create policy jr_insert on join_requests for insert
    with check (user_id = auth.uid());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy jr_read on join_requests for select
    using (user_id = auth.uid() or is_manager(club_id));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy jr_update on join_requests for update
    using (is_manager(club_id));
exception when duplicate_object then null; end $$;

-- club_invites: managers full control; everyone can read by token to accept
do $$ begin
  create policy inv_mgr on club_invites for all
    using (is_manager(club_id)) with check (is_manager(club_id));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy inv_public_read on club_invites for select
    using (true);
exception when duplicate_object then null; end $$;

-- =====================================================================
-- RPCs
-- =====================================================================

-- List all clubs with member count (any authenticated user can browse)
create or replace function get_public_clubs()
returns table(id uuid, name text, member_count bigint)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, count(cm.user_id)::bigint
  from clubs c
  left join club_members cm on cm.club_id = c.id
  group by c.id, c.name
  order by count(cm.user_id) desc, c.name;
$$;

-- Player requests to join a club
create or replace function request_join(p_club_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_email text;
  v_name  text;
begin
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
    on conflict (club_id, user_id) do nothing;
end;
$$;

-- Manager approves a join request → adds to club_members + players
create or replace function approve_join(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_club uuid;
  v_user uuid;
  v_name text;
begin
  select club_id, user_id, user_name
    into v_club, v_user, v_name
    from join_requests where id = p_request_id;

  if not is_manager(v_club) then
    raise exception 'Not authorized';
  end if;

  insert into club_members(club_id, user_id, role)
    values (v_club, v_user, 'player')
    on conflict do nothing;

  insert into players(club_id, user_id, display_name)
    select v_club, v_user, v_name
    where not exists (
      select 1 from players where club_id = v_club and user_id = v_user
    );

  update join_requests set status = 'approved' where id = p_request_id;
end;
$$;

-- Manager rejects a join request
create or replace function reject_join(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_club uuid;
begin
  select club_id into v_club from join_requests where id = p_request_id;
  if not is_manager(v_club) then raise exception 'Not authorized'; end if;
  update join_requests set status = 'rejected' where id = p_request_id;
end;
$$;

-- Manager generates an invite link, returns the token
create or replace function invite_member(p_club_id uuid, p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare v_token text;
begin
  if not is_manager(p_club_id) then raise exception 'Not authorized'; end if;
  insert into club_invites(club_id, email, invited_by)
    values (p_club_id, lower(trim(p_email)), auth.uid())
    returning token into v_token;
  return v_token;
end;
$$;

-- User accepts an invite by token → joins as player
create or replace function accept_invite(p_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_inv  record;
  v_name text;
begin
  select * into v_inv
    from club_invites
    where token = p_token and status = 'pending' and expires_at > now();

  if not found then
    raise exception 'Invalid or expired invite link';
  end if;

  select coalesce(
    raw_user_meta_data->>'full_name',
    raw_user_meta_data->>'name',
    split_part(email, '@', 1)
  ) into v_name from auth.users where id = auth.uid();

  insert into club_members(club_id, user_id, role)
    values (v_inv.club_id, auth.uid(), 'player')
    on conflict do nothing;

  insert into players(club_id, user_id, display_name)
    select v_inv.club_id, auth.uid(), v_name
    where not exists (
      select 1 from players where club_id = v_inv.club_id and user_id = auth.uid()
    );

  update club_invites set status = 'accepted' where id = v_inv.id;
  return v_inv.club_id;
end;
$$;
