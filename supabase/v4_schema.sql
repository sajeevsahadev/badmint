-- =====================================================================
-- Badmint v4 — Match deletion + Player active/inactive
-- Run in Supabase SQL Editor AFTER v3_schema.sql
-- =====================================================================

-- ── Add is_active column to players ──
alter table players add column if not exists is_active boolean not null default true;

-- ── Update v_leaderboard to exclude inactive players ──
create or replace view v_leaderboard as
with stats as (
  select
    p.id, p.club_id, p.display_name, p.elo,
    coalesce(att.days,0)                  as days_played,
    coalesce(w.wins,0)                    as wins,
    coalesce(g.games,0)                   as games,
    coalesce(cfg.elo_weight,0.7)          as ew,
    coalesce(cfg.participation_weight,0.3) as pw
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
  where p.is_active = true                 -- ← inactive players excluded
),
bounds as (
  select club_id,
    min(elo) emin, max(elo) emax,
    min(days_played) dmin, max(days_played) dmax
  from stats group by club_id
)
select
  s.id, s.club_id, s.display_name,
  round(s.elo)::int                                         as elo,
  s.days_played, s.games, s.wins,
  case when s.games>0 then round(100.0*s.wins/s.games) else 0 end as win_pct,
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

-- ── Also exclude inactive players from top scorers ──
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
where p.is_active = true and coalesce(vl.games, 0) >= 1;

-- ── Toggle player active/inactive (managers only) ──
create or replace function toggle_player_active(p_player_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_club       uuid;
  v_new_status boolean;
begin
  select club_id into v_club from players where id = p_player_id;
  if not is_manager(v_club) then raise exception 'Not authorized'; end if;
  update players set is_active = not is_active
    where id = p_player_id
    returning is_active into v_new_status;
  return v_new_status;
end;
$$;

-- ── Delete match + full Elo recalculation from scratch ──
-- Deletes the match then replays ALL remaining matches in chronological
-- order to produce correct Elo values. Also updates elo_before/elo_after
-- in match_participants so the history view stays accurate.
create or replace function delete_match(p_match_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_club      uuid;
  v_start_elo integer;
  v_k         integer;
  m           record;
  v_a_players uuid[];
  v_b_players uuid[];
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
  select club_id into v_club from matches where id = p_match_id;
  if v_club is null then raise exception 'Match not found'; end if;
  if not is_manager(v_club) then raise exception 'Not authorized'; end if;

  select coalesce(starting_elo, 1000), coalesce(k_factor, 24)
  into v_start_elo, v_k
  from ranking_config where club_id = v_club;

  -- 1. Delete the target match (cascades to match_sides + match_participants)
  delete from matches where id = p_match_id;

  -- 2. Reset ALL club players to starting Elo (active and inactive — history is neutral)
  update players set elo = v_start_elo where club_id = v_club;

  -- 3. Rebuild attendance from scratch
  delete from attendance where club_id = v_club;

  -- 4. Replay remaining matches in chronological order
  for m in
    select
      ma.played_on,
      sa.id    as side_a_id,
      sb.id    as side_b_id,
      sa.score as score_a,
      sb.score as score_b
    from matches ma
    join match_sides sa on sa.match_id = ma.id and sa.side = 'A'
    join match_sides sb on sb.match_id = ma.id and sb.side = 'B'
    where ma.club_id = v_club
    order by ma.played_on, ma.created_at
  loop
    select array_agg(player_id) into v_a_players
      from match_participants where match_side_id = m.side_a_id;
    select array_agg(player_id) into v_b_players
      from match_participants where match_side_id = m.side_b_id;

    v_a_win := m.score_a > m.score_b;
    v_res_a := case when v_a_win then 1 else 0 end;
    v_res_b := 1 - v_res_a;

    select avg(elo) into v_a_avg from players where id = any(v_a_players);
    select avg(elo) into v_b_avg from players where id = any(v_b_players);

    v_exp_a := 1.0 / (1.0 + power(10, (v_b_avg - v_a_avg) / 400.0));
    v_exp_b := 1.0 / (1.0 + power(10, (v_a_avg - v_b_avg) / 400.0));

    foreach pid in array v_a_players loop
      select elo into v_old from players where id = pid;
      v_new := v_old + v_k * (v_res_a - v_exp_a);
      update players set elo = v_new where id = pid;
      update match_participants
        set elo_before = v_old, elo_after = v_new
        where match_side_id = m.side_a_id and player_id = pid;
    end loop;

    foreach pid in array v_b_players loop
      select elo into v_old from players where id = pid;
      v_new := v_old + v_k * (v_res_b - v_exp_b);
      update players set elo = v_new where id = pid;
      update match_participants
        set elo_before = v_old, elo_after = v_new
        where match_side_id = m.side_b_id and player_id = pid;
    end loop;

    -- Rebuild attendance
    insert into attendance(club_id, player_id, played_on)
    select v_club, unnest(v_a_players || v_b_players), m.played_on
    on conflict (player_id, played_on) do nothing;
  end loop;
end;
$$;

grant execute on function delete_match(uuid)            to authenticated;
grant execute on function toggle_player_active(uuid)    to authenticated;
