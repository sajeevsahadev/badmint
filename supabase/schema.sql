-- =====================================================================
-- ShuttleRank — Supabase schema (PostgreSQL)
-- Run this in Supabase SQL Editor once. Idempotent-ish; drops first.
-- =====================================================================

-- ---------- CLEAN (safe re-run during dev) ----------
drop view  if exists v_head_to_head      cascade;
drop view  if exists v_best_pairs        cascade;
drop view  if exists v_leaderboard       cascade;
drop table if exists match_participants  cascade;
drop table if exists match_sides         cascade;
drop table if exists matches             cascade;
drop table if exists attendance          cascade;
drop table if exists players             cascade;
drop table if exists ranking_config      cascade;
drop table if exists club_members        cascade;
drop table if exists clubs               cascade;

-- ---------- CLUBS ----------
create table clubs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_by  uuid not null references auth.users(id),
  created_at  timestamptz not null default now()
);

-- ---------- MEMBERSHIP (who can do what in a club) ----------
-- role: 'owner' | 'manager' | 'player'
create table club_members (
  club_id   uuid not null references clubs(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  role      text not null default 'player' check (role in ('owner','manager','player')),
  joined_at timestamptz not null default now(),
  primary key (club_id, user_id)
);

-- ---------- RANKING CONFIG (per club, tunable) ----------
create table ranking_config (
  club_id             uuid primary key references clubs(id) on delete cascade,
  elo_weight          numeric not null default 0.7,
  participation_weight numeric not null default 0.3,
  k_factor            integer not null default 24,
  starting_elo        integer not null default 1000
);

-- ---------- PLAYERS (a roster record; user_id optional for guests) ----------
create table players (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references clubs(id) on delete cascade,
  display_name text not null,
  user_id      uuid references auth.users(id),
  elo          numeric not null default 1000,
  created_at   timestamptz not null default now()
);
create index on players (club_id);

-- ---------- ATTENDANCE (one row per player per day) ----------
create table attendance (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references clubs(id) on delete cascade,
  player_id  uuid not null references players(id) on delete cascade,
  played_on  date not null default current_date,
  unique (player_id, played_on)
);
create index on attendance (club_id);

-- ---------- MATCHES (doubles only) ----------
create table matches (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references clubs(id) on delete cascade,
  played_on   date not null default current_date,
  created_by  uuid not null references auth.users(id),
  created_at  timestamptz not null default now()
);
create index on matches (club_id, played_on);

-- two rows per match: side 'A' and side 'B'
create table match_sides (
  id        uuid primary key default gen_random_uuid(),
  match_id  uuid not null references matches(id) on delete cascade,
  side      text not null check (side in ('A','B')),
  score     integer not null default 0,
  is_winner boolean not null default false,
  unique (match_id, side)
);

-- two participants per side; stores Elo snapshot for history/most-improved
create table match_participants (
  id            uuid primary key default gen_random_uuid(),
  match_side_id uuid not null references match_sides(id) on delete cascade,
  player_id     uuid not null references players(id) on delete cascade,
  elo_before    numeric,
  elo_after     numeric
);
create index on match_participants (player_id);

-- =====================================================================
-- ELO ENGINE — called as an RPC from the app inside one transaction.
-- Records the match, both sides, 4 participants, updates player Elo,
-- and marks attendance for the 4 players on that date.
-- =====================================================================
create or replace function record_match(
  p_club_id   uuid,
  p_played_on date,
  p_side_a    uuid[],   -- exactly 2 player ids
  p_side_b    uuid[],   -- exactly 2 player ids
  p_score_a   integer,
  p_score_b   integer
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match_id   uuid;
  v_side_a_id  uuid;
  v_side_b_id  uuid;
  v_k          integer;
  v_a_avg      numeric;
  v_b_avg      numeric;
  v_exp_a      numeric;
  v_exp_b      numeric;
  v_res_a      numeric;
  v_res_b      numeric;
  v_a_win      boolean;
  pid          uuid;
  v_old        numeric;
  v_new        numeric;
begin
  -- authorization: caller must be owner/manager of the club
  if not exists (
    select 1 from club_members
    where club_id = p_club_id and user_id = auth.uid()
      and role in ('owner','manager')
  ) then
    raise exception 'Not authorized: only owners/managers can record matches';
  end if;

  if array_length(p_side_a,1) <> 2 or array_length(p_side_b,1) <> 2 then
    raise exception 'Each side must have exactly 2 players';
  end if;

  select coalesce(k_factor,24) into v_k from ranking_config where club_id = p_club_id;
  if v_k is null then v_k := 24; end if;

  v_a_win := p_score_a > p_score_b;
  v_res_a := case when v_a_win then 1 else 0 end;
  v_res_b := 1 - v_res_a;

  -- side average Elo
  select avg(elo) into v_a_avg from players where id = any(p_side_a);
  select avg(elo) into v_b_avg from players where id = any(p_side_b);

  v_exp_a := 1.0 / (1.0 + power(10, (v_b_avg - v_a_avg)/400.0));
  v_exp_b := 1.0 / (1.0 + power(10, (v_a_avg - v_b_avg)/400.0));

  insert into matches(club_id, played_on, created_by)
    values (p_club_id, coalesce(p_played_on, current_date), auth.uid())
    returning id into v_match_id;

  insert into match_sides(match_id, side, score, is_winner)
    values (v_match_id,'A',p_score_a, v_a_win) returning id into v_side_a_id;
  insert into match_sides(match_id, side, score, is_winner)
    values (v_match_id,'B',p_score_b, not v_a_win) returning id into v_side_b_id;

  -- side A players
  foreach pid in array p_side_a loop
    select elo into v_old from players where id = pid;
    v_new := v_old + v_k * (v_res_a - v_exp_a);
    update players set elo = v_new where id = pid;
    insert into match_participants(match_side_id, player_id, elo_before, elo_after)
      values (v_side_a_id, pid, v_old, v_new);
  end loop;

  -- side B players
  foreach pid in array p_side_b loop
    select elo into v_old from players where id = pid;
    v_new := v_old + v_k * (v_res_b - v_exp_b);
    update players set elo = v_new where id = pid;
    insert into match_participants(match_side_id, player_id, elo_before, elo_after)
      values (v_side_b_id, pid, v_old, v_new);
  end loop;

  -- attendance for all 4 (idempotent per day)
  insert into attendance(club_id, player_id, played_on)
  select p_club_id, x, coalesce(p_played_on, current_date)
  from unnest(p_side_a || p_side_b) as x
  on conflict (player_id, played_on) do nothing;

  return v_match_id;
end;
$$;

-- helper: create a club + make caller owner + default config, atomically
create or replace function create_club(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  insert into clubs(name, created_by) values (p_name, auth.uid()) returning id into v_id;
  insert into club_members(club_id, user_id, role) values (v_id, auth.uid(), 'owner');
  insert into ranking_config(club_id) values (v_id);
  return v_id;
end;
$$;

-- =====================================================================
-- VIEWS — ranking & analytics (all SQL, no app-side math)
-- =====================================================================

-- LEADERBOARD: skill (Elo) + participation, normalized 0-100, composite.
create or replace view v_leaderboard as
with stats as (
  select
    p.id, p.club_id, p.display_name, p.elo,
    coalesce(att.days,0)                                   as days_played,
    coalesce(w.wins,0)                                     as wins,
    coalesce(g.games,0)                                    as games,
    coalesce(cfg.elo_weight,0.7)                           as ew,
    coalesce(cfg.participation_weight,0.3)                 as pw
  from players p
  left join ranking_config cfg on cfg.club_id = p.club_id
  left join (
    select player_id, count(*) days from attendance group by player_id
  ) att on att.player_id = p.id
  left join (
    select mp.player_id, count(*) games
    from match_participants mp group by mp.player_id
  ) g on g.player_id = p.id
  left join (
    select mp.player_id, count(*) wins
    from match_participants mp
    join match_sides ms on ms.id = mp.match_side_id and ms.is_winner
    group by mp.player_id
  ) w on w.player_id = p.id
),
bounds as (
  select club_id,
    min(elo) emin, max(elo) emax,
    min(days_played) dmin, max(days_played) dmax
  from stats group by club_id
)
select
  s.id, s.club_id, s.display_name,
  round(s.elo)::int                                        as elo,
  s.days_played, s.games, s.wins,
  case when s.games>0 then round(100.0*s.wins/s.games) else 0 end as win_pct,
  -- normalize within club (avoid div by zero)
  round(100 * case when b.emax=b.emin then 0.5
       else (s.elo-b.emin)/(b.emax-b.emin) end, 1)         as elo_score,
  round(100 * case when b.dmax=b.dmin then 0.5
       else (s.days_played-b.dmin)::numeric/(b.dmax-b.dmin) end, 1) as part_score,
  round(
    s.ew * 100 * case when b.emax=b.emin then 0.5
         else (s.elo-b.emin)/(b.emax-b.emin) end
   + s.pw * 100 * case when b.dmax=b.dmin then 0.5
         else (s.days_played-b.dmin)::numeric/(b.dmax-b.dmin) end
  ,1)                                                       as composite,
  rank() over (
    partition by s.club_id
    order by (
      s.ew * case when b.emax=b.emin then 0.5 else (s.elo-b.emin)/(b.emax-b.emin) end
    + s.pw * case when b.dmax=b.dmin then 0.5 else (s.days_played-b.dmin)::numeric/(b.dmax-b.dmin) end
    ) desc
  )                                                         as club_rank
from stats s join bounds b on b.club_id = s.club_id;

-- BEST PAIRS: which two players win most together.
create or replace view v_best_pairs as
with pair_games as (
  select
    ms.id as side_id, ms.match_id, ms.is_winner, mp.player_id, p.club_id
  from match_sides ms
  join match_participants mp on mp.match_side_id = ms.id
  join players p on p.id = mp.player_id
),
pairs as (
  select
    a.club_id,
    least(a.player_id,b.player_id)  as p1,
    greatest(a.player_id,b.player_id) as p2,
    a.is_winner
  from pair_games a
  join pair_games b
    on a.side_id = b.side_id and a.player_id < b.player_id
)
select
  pr.club_id, pr.p1, pr.p2,
  n1.display_name as p1_name, n2.display_name as p2_name,
  count(*)                                          as games,
  sum(case when pr.is_winner then 1 else 0 end)     as wins,
  round(100.0*sum(case when pr.is_winner then 1 else 0 end)/count(*),1) as win_pct
from pairs pr
join players n1 on n1.id = pr.p1
join players n2 on n2.id = pr.p2
group by pr.club_id, pr.p1, pr.p2, n1.display_name, n2.display_name
having count(*) >= 1
order by win_pct desc, games desc;

-- HEAD TO HEAD: every time two players were on OPPOSITE sides.
create or replace view v_head_to_head as
with sides as (
  select ms.match_id, ms.side, ms.is_winner, mp.player_id, p.club_id
  from match_sides ms
  join match_participants mp on mp.match_side_id = ms.id
  join players p on p.id = mp.player_id
)
select
  s1.club_id,
  s1.player_id as player_a, s2.player_id as player_b,
  count(*) as meetings,
  sum(case when s1.is_winner then 1 else 0 end) as a_wins,
  sum(case when s2.is_winner then 1 else 0 end) as b_wins
from sides s1
join sides s2
  on s1.match_id = s2.match_id and s1.side <> s2.side and s1.player_id <> s2.player_id
group by s1.club_id, s1.player_id, s2.player_id;

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
alter table clubs              enable row level security;
alter table club_members       enable row level security;
alter table ranking_config     enable row level security;
alter table players            enable row level security;
alter table attendance         enable row level security;
alter table matches            enable row level security;
alter table match_sides        enable row level security;
alter table match_participants enable row level security;

-- membership lookup helper (avoids recursive RLS)
create or replace function is_member(c uuid) returns boolean
language sql security definer stable set search_path=public as $$
  select exists(select 1 from club_members where club_id=c and user_id=auth.uid());
$$;
create or replace function is_manager(c uuid) returns boolean
language sql security definer stable set search_path=public as $$
  select exists(select 1 from club_members where club_id=c and user_id=auth.uid()
                and role in ('owner','manager'));
$$;

-- CLUBS: members can read; anyone logged in can create (via create_club).
create policy clubs_read on clubs for select using (is_member(id));
create policy clubs_ins  on clubs for insert with check (created_by = auth.uid());

-- CLUB_MEMBERS: members read their clubs; managers manage rows.
create policy cm_read on club_members for select using (is_member(club_id));
create policy cm_write on club_members for all
  using (is_manager(club_id)) with check (is_manager(club_id));

-- CONFIG: members read, managers edit.
create policy cfg_read on ranking_config for select using (is_member(club_id));
create policy cfg_write on ranking_config for all
  using (is_manager(club_id)) with check (is_manager(club_id));

-- PLAYERS / ATTENDANCE / MATCHES etc: members read, managers write.
create policy pl_read on players for select using (is_member(club_id));
create policy pl_write on players for all
  using (is_manager(club_id)) with check (is_manager(club_id));

create policy at_read on attendance for select using (is_member(club_id));
create policy at_write on attendance for all
  using (is_manager(club_id)) with check (is_manager(club_id));

create policy mt_read on matches for select using (is_member(club_id));
create policy mt_write on matches for all
  using (is_manager(club_id)) with check (is_manager(club_id));

create policy ms_read on match_sides for select
  using (exists(select 1 from matches m where m.id=match_id and is_member(m.club_id)));
create policy ms_write on match_sides for all
  using (exists(select 1 from matches m where m.id=match_id and is_manager(m.club_id)))
  with check (exists(select 1 from matches m where m.id=match_id and is_manager(m.club_id)));

create policy mp_read on match_participants for select
  using (exists(select 1 from match_sides s join matches m on m.id=s.match_id
               where s.id=match_side_id and is_member(m.club_id)));
create policy mp_write on match_participants for all
  using (exists(select 1 from match_sides s join matches m on m.id=s.match_id
               where s.id=match_side_id and is_manager(m.club_id)))
  with check (exists(select 1 from match_sides s join matches m on m.id=s.match_id
               where s.id=match_side_id and is_manager(m.club_id)));
