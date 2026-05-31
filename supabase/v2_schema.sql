-- =====================================================================
-- Badmint v2 — Additive migration
-- Run in Supabase SQL Editor AFTER the original schema.sql
-- Safe to re-run (uses IF NOT EXISTS / CREATE OR REPLACE)
-- =====================================================================

-- ── User profiles (public nickname, optional phone/bio) ──
create table if not exists user_profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  nickname   text,
  phone      text,
  bio        text,
  avatar_url text,
  updated_at timestamptz default now()
);
alter table user_profiles enable row level security;
do $$ begin
  create policy up_read  on user_profiles for select using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy up_write on user_profiles for all
    using (user_id = auth.uid()) with check (user_id = auth.uid());
exception when duplicate_object then null; end $$;

-- ── Club location / facility (all optional) ──
alter table clubs add column if not exists emirates         text
  check (emirates in ('Abu Dhabi','Dubai','Sharjah','Ajman',
                      'Umm Al Quwain','Ras Al Khaimah','Fujairah'));
alter table clubs add column if not exists facility_name    text;
alter table clubs add column if not exists facility_address text;
alter table clubs add column if not exists maps_url         text;
alter table clubs add column if not exists description      text;

-- ── Match number + optional display name ──
alter table matches add column if not exists match_number  int;
alter table matches add column if not exists display_name  text;

-- Trigger: auto-assign sequential match_number per club on insert
create or replace function fn_auto_match_number()
returns trigger language plpgsql as $$
declare v_num int;
begin
  select coalesce(max(match_number), 0) + 1 into v_num
  from matches where club_id = NEW.club_id;
  NEW.match_number := v_num;
  if NEW.display_name is null then
    NEW.display_name := 'Match #' || v_num;
  end if;
  return NEW;
end;
$$;
drop trigger if exists trg_auto_match_number on matches;
create trigger trg_auto_match_number
  before insert on matches
  for each row execute function fn_auto_match_number();

-- Drop old 6-param overload so the 7-param version (with default) is unambiguous
drop function if exists record_match(uuid, date, uuid[], uuid[], integer, integer);

-- ── Updated record_match — adds optional p_display_name ──
create or replace function record_match(
  p_club_id      uuid,
  p_played_on    date,
  p_side_a       uuid[],
  p_side_b       uuid[],
  p_score_a      integer,
  p_score_b      integer,
  p_display_name text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_match_id  uuid;
  v_side_a_id uuid;
  v_side_b_id uuid;
  v_k         integer;
  v_a_avg     numeric;
  v_b_avg     numeric;
  v_exp_a     numeric;
  v_exp_b     numeric;
  v_res_a     numeric;
  v_res_b     numeric;
  v_a_win     boolean;
  pid         uuid;
  v_old       numeric;
  v_new       numeric;
begin
  if not exists (
    select 1 from club_members
    where club_id = p_club_id and user_id = auth.uid()
      and role in ('owner','manager')
  ) then raise exception 'Not authorized: only owners/managers can record matches'; end if;

  if array_length(p_side_a,1) <> 2 or array_length(p_side_b,1) <> 2 then
    raise exception 'Each side must have exactly 2 players';
  end if;

  select coalesce(k_factor,24) into v_k from ranking_config where club_id = p_club_id;
  if v_k is null then v_k := 24; end if;

  v_a_win := p_score_a > p_score_b;
  v_res_a := case when v_a_win then 1 else 0 end;
  v_res_b := 1 - v_res_a;

  select avg(elo) into v_a_avg from players where id = any(p_side_a);
  select avg(elo) into v_b_avg from players where id = any(p_side_b);
  v_exp_a := 1.0 / (1.0 + power(10, (v_b_avg - v_a_avg)/400.0));
  v_exp_b := 1.0 / (1.0 + power(10, (v_a_avg - v_b_avg)/400.0));

  insert into matches(club_id, played_on, created_by, display_name)
    values (p_club_id, coalesce(p_played_on, current_date), auth.uid(), p_display_name)
    returning id into v_match_id;

  insert into match_sides(match_id, side, score, is_winner)
    values (v_match_id,'A',p_score_a, v_a_win)     returning id into v_side_a_id;
  insert into match_sides(match_id, side, score, is_winner)
    values (v_match_id,'B',p_score_b, not v_a_win) returning id into v_side_b_id;

  foreach pid in array p_side_a loop
    select elo into v_old from players where id = pid;
    v_new := v_old + v_k * (v_res_a - v_exp_a);
    update players set elo = v_new where id = pid;
    insert into match_participants(match_side_id, player_id, elo_before, elo_after)
      values (v_side_a_id, pid, v_old, v_new);
  end loop;

  foreach pid in array p_side_b loop
    select elo into v_old from players where id = pid;
    v_new := v_old + v_k * (v_res_b - v_exp_b);
    update players set elo = v_new where id = pid;
    insert into match_participants(match_side_id, player_id, elo_before, elo_after)
      values (v_side_b_id, pid, v_old, v_new);
  end loop;

  insert into attendance(club_id, player_id, played_on)
  select p_club_id, x, coalesce(p_played_on, current_date)
  from unnest(p_side_a || p_side_b) as x
  on conflict (player_id, played_on) do nothing;

  return v_match_id;
end;
$$;

-- ── Club ranking view ──
-- Score = (activity_per_member + engagement) × recency + 10 base
-- activity_per_member: matches_30d / active_30d × 15, capped at 50
-- engagement: active_30d / total_members × 25
-- recency: 1.0 / 0.7 / 0.4 / 0.1 based on days since last match
create or replace view v_club_rankings as
with
  m_stats as (
    select club_id,
      count(*) filter (where played_on >= current_date - 30) as m30,
      max(played_on) as last_played
    from matches group by club_id
  ),
  a_stats as (
    select club_id, count(distinct player_id) as active_30d
    from attendance where played_on >= current_date - 30
    group by club_id
  ),
  mb_stats as (
    select club_id, count(*) as total_members
    from club_members group by club_id
  )
select
  c.id               as club_id,
  c.name,
  c.emirates,
  c.facility_name,
  c.facility_address,
  c.maps_url,
  c.description,
  coalesce(m.m30, 0)            as matches_30d,
  coalesce(a.active_30d, 0)     as active_30d,
  coalesce(mb.total_members, 0) as total_members,
  m.last_played,
  round((
    least(
      case when coalesce(a.active_30d,0) > 0
           then coalesce(m.m30,0)::numeric / a.active_30d * 15
           else 0 end,
      50
    )
    + case when coalesce(mb.total_members,0) > 0
           then coalesce(a.active_30d,0)::numeric / mb.total_members * 25
           else 0 end
  ) * case
        when m.last_played >= current_date - 7  then 1.0
        when m.last_played >= current_date - 14 then 0.7
        when m.last_played >= current_date - 30 then 0.4
        else 0.1
      end
  + 10, 1) as club_score,
  rank() over (
    order by (
      least(
        case when coalesce(a.active_30d,0) > 0
             then coalesce(m.m30,0)::numeric / a.active_30d * 15
             else 0 end,
        50
      )
      + case when coalesce(mb.total_members,0) > 0
             then coalesce(a.active_30d,0)::numeric / mb.total_members * 25
             else 0 end
    ) * case
          when m.last_played >= current_date - 7  then 1.0
          when m.last_played >= current_date - 14 then 0.7
          when m.last_played >= current_date - 30 then 0.4
          else 0.1
        end
    desc nulls last
  ) as club_rank
from clubs c
left join m_stats  m  on m.club_id  = c.id
left join a_stats  a  on a.club_id  = c.id
left join mb_stats mb on mb.club_id = c.id;

-- ── Top scorers across all clubs (Elo is cross-club comparable) ──
create or replace view v_top_scorers as
select
  p.id                                                  as player_id,
  p.club_id,
  c.name                                                as club_name,
  c.emirates,
  coalesce(up.nickname, p.display_name)                 as public_name,
  round(p.elo)::int                                     as elo,
  coalesce(vl.games, 0)                                 as games,
  coalesce(vl.wins, 0)                                  as wins,
  coalesce(vl.win_pct, 0)                               as win_pct,
  coalesce(vl.days_played, 0)                           as days_played,
  rank() over (order by p.elo desc)                     as global_rank
from players p
join clubs c on c.id = p.club_id
left join v_leaderboard vl on vl.id = p.id
left join user_profiles up on up.user_id = p.user_id
where coalesce(vl.games, 0) >= 3;

-- ── Security-definer RPCs (bypass RLS for public endpoints) ──

-- Drop old versions whose signatures changed
drop function if exists get_public_clubs();
drop function if exists get_top_scorers(int);

-- Browse all clubs with ranking info (public — any authenticated user)
create or replace function get_public_clubs()
returns table(
  id uuid, name text, member_count bigint, emirates text,
  facility_name text, facility_address text, maps_url text,
  matches_30d bigint, active_30d bigint, club_score numeric,
  last_played date, club_rank bigint
)
language sql stable security definer set search_path = public as $$
  select
    cr.club_id, cr.name, cr.total_members::bigint, cr.emirates,
    cr.facility_name, cr.facility_address, cr.maps_url,
    cr.matches_30d::bigint, cr.active_30d::bigint, cr.club_score,
    cr.last_played, cr.club_rank
  from v_club_rankings cr
  order by cr.club_rank;
$$;

-- Top scorers (public)
create or replace function get_top_scorers(p_limit int default 50)
returns table(
  player_id uuid, public_name text, club_name text, emirates text,
  elo int, games int, win_pct numeric, global_rank bigint
)
language sql stable security definer set search_path = public as $$
  select player_id, public_name, club_name, emirates, elo, games, win_pct, global_rank
  from v_top_scorers order by global_rank limit p_limit;
$$;

-- Grant execute to authenticated role (anon fallback for public pages)
grant execute on function get_public_clubs()         to authenticated, anon;
grant execute on function get_top_scorers(int)       to authenticated, anon;
grant execute on function request_join(uuid)         to authenticated;
grant execute on function approve_join(uuid)         to authenticated;
grant execute on function reject_join(uuid)          to authenticated;
grant execute on function invite_member(uuid, text)  to authenticated;
grant execute on function accept_invite(text)        to authenticated;

-- Upsert user profile
create or replace function upsert_profile(
  p_nickname text,
  p_phone    text default null,
  p_bio      text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into user_profiles(user_id, nickname, phone, bio, updated_at)
    values (auth.uid(), p_nickname, p_phone, p_bio, now())
    on conflict (user_id) do update set
      nickname   = excluded.nickname,
      phone      = coalesce(excluded.phone, user_profiles.phone),
      bio        = coalesce(excluded.bio, user_profiles.bio),
      updated_at = now();
end;
$$;

-- Update club facility info (managers only)
create or replace function update_club_facility(
  p_club_id        uuid,
  p_emirates       text     default null,
  p_facility_name  text     default null,
  p_facility_address text   default null,
  p_maps_url       text     default null,
  p_description    text     default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_manager(p_club_id) then raise exception 'Not authorized'; end if;
  update clubs set
    emirates         = coalesce(p_emirates,         emirates),
    facility_name    = coalesce(p_facility_name,    facility_name),
    facility_address = coalesce(p_facility_address, facility_address),
    maps_url         = coalesce(p_maps_url,         maps_url),
    description      = coalesce(p_description,      description)
  where id = p_club_id;
end;
$$;

-- Rename a match (managers)
create or replace function rename_match(p_match_id uuid, p_name text)
returns void language plpgsql security definer set search_path = public as $$
declare v_club uuid;
begin
  select club_id into v_club from matches where id = p_match_id;
  if not is_manager(v_club) then raise exception 'Not authorized'; end if;
  update matches set display_name = p_name where id = p_match_id;
end;
$$;
