-- v147: Analysis VERSIONS + player photo thumbnails.
-- Every analysis run (Simple or Deep) is now an analysis_runs row ("Version N"). Re-running creates
-- Version N+1 and KEEPS all earlier versions — nothing is deleted. Existing results are backfilled as
-- Version 1. Also adds per-player photo crops (video_player_tags.thumb_path / video_person_tracks.thumb_path)
-- and an index_status for the quick "find the people" pass that produces those crops.
-- Applied to project bdmiirppiyopmdfrztoz via MCP.

-- 1. Runs ------------------------------------------------------------------------------------
create table if not exists public.analysis_runs (
  id          uuid primary key default gen_random_uuid(),
  video_id    uuid not null references public.match_videos(id) on delete cascade,
  kind        text not null check (kind in ('simple','deep')),
  version     integer not null,
  status      text not null default 'analyzing' check (status in ('analyzing','done','failed')),
  error       text,
  is_mock     boolean not null default false,
  engine      text,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  finished_at timestamptz,
  unique (video_id, kind, version)
);
create index if not exists idx_runs_video on public.analysis_runs(video_id, kind, version desc);
alter table public.analysis_runs enable row level security;
drop policy if exists runs_sel on public.analysis_runs;
create policy runs_sel on public.analysis_runs for select using (public.can_access_video(video_id));

alter table public.player_metrics      add column if not exists run_id uuid references public.analysis_runs(id) on delete cascade;
alter table public.analysis_reports    add column if not exists run_id uuid references public.analysis_runs(id) on delete cascade;
alter table public.analysis_shots      add column if not exists run_id uuid references public.analysis_runs(id) on delete cascade;
alter table public.analysis_commentary add column if not exists run_id uuid references public.analysis_runs(id) on delete cascade;

-- 2. Photos + index status ---------------------------------------------------------------------
alter table public.video_player_tags add column if not exists thumb_path text;
alter table public.match_videos add column if not exists index_status text not null default 'none'
  check (index_status in ('none','indexing','done','failed'));

-- 3. Backfill existing results as Version 1 ----------------------------------------------------
insert into public.analysis_runs (video_id, kind, version, status, is_mock, engine, created_at, finished_at)
select mv.id, 'simple', 1, case when mv.status = 'failed' then 'failed' else 'done' end, mv.is_mock, 'pose-v1',
       coalesce(mv.analyzed_at, mv.created_at), mv.analyzed_at
  from public.match_videos mv
 where exists (select 1 from public.player_metrics m where m.video_id = mv.id)
on conflict do nothing;

insert into public.analysis_runs (video_id, kind, version, status, is_mock, engine, created_at, finished_at)
select mv.id, 'deep', 1, case when mv.deep_status = 'failed' then 'failed' else 'done' end, mv.is_deep_mock, 'pose-v1',
       coalesce(mv.deep_requested_at, mv.created_at), coalesce(mv.deep_requested_at, mv.created_at)
  from public.match_videos mv
 where exists (select 1 from public.analysis_shots s where s.video_id = mv.id)
on conflict do nothing;

update public.player_metrics m set run_id = r.id from public.analysis_runs r
 where m.run_id is null and r.video_id = m.video_id and r.kind = 'simple' and r.version = 1;
update public.analysis_reports a set run_id = r.id from public.analysis_runs r
 where a.run_id is null and r.video_id = a.video_id and r.kind = 'simple' and r.version = 1;
update public.analysis_shots s set run_id = r.id from public.analysis_runs r
 where s.run_id is null and r.video_id = s.video_id and r.kind = 'deep' and r.version = 1;
update public.analysis_commentary c set run_id = r.id from public.analysis_runs r
 where c.run_id is null and r.video_id = c.video_id and r.kind = 'deep' and r.version = 1;

-- 4. Uniqueness is now per run (not per video) --------------------------------------------------
alter table public.player_metrics   drop constraint if exists player_metrics_video_id_tag_id_key;
alter table public.analysis_reports drop constraint if exists analysis_reports_video_id_tag_id_lens_key;
create unique index if not exists uq_pm_run_tag      on public.player_metrics(run_id, tag_id);
create unique index if not exists uq_ar_run_tag_lens on public.analysis_reports(run_id, tag_id, lens);
create index if not exists idx_shots_run on public.analysis_shots(run_id);
create index if not exists idx_comm_run  on public.analysis_commentary(run_id);

-- 5. Run lifecycle --------------------------------------------------------------------------------
create or replace function public.start_analysis_run(p_video_id uuid, p_kind text, p_is_mock boolean default false,
                                                     p_engine text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ver int;
begin
  perform pg_advisory_xact_lock(hashtext(p_video_id::text || p_kind));
  select coalesce(max(version), 0) + 1 into v_ver from public.analysis_runs where video_id = p_video_id and kind = p_kind;
  insert into public.analysis_runs (video_id, kind, version, status, is_mock, engine)
  values (p_video_id, p_kind, v_ver, 'analyzing', p_is_mock, p_engine) returning id into v_id;
  if p_kind = 'simple' then
    update public.match_videos set status = 'analyzing', error = null where id = p_video_id;
  else
    update public.match_videos set deep_status = 'analyzing', deep_error = null, deep_requested_at = now() where id = p_video_id;
  end if;
  return v_id;
end;
$$;

create or replace function public._run_or_latest(p_video_id uuid, p_kind text, p_run_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(p_run_id,
    (select id from public.analysis_runs where video_id = p_video_id and kind = p_kind and status = 'analyzing'
      order by version desc limit 1),
    (select id from public.analysis_runs where video_id = p_video_id and kind = p_kind order by version desc limit 1));
$$;

drop function if exists public.build_player_reports(uuid, boolean);
create or replace function public.build_player_reports(p_video_id uuid, p_is_mock boolean, p_run_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record; v_m jsonb; v_coach jsonb; v_well text; v_hold text; v_opp text; v_score int; v_by text;
begin
  v_by := case when p_is_mock then 'mock' else 'engine' end;
  for r in select tag_id, metrics from public.player_metrics where video_id = p_video_id and run_id = p_run_id loop
    v_m := r.metrics;
    v_coach := public.match_rubric('coach', v_m);
    v_well := case when coalesce((v_m->>'coverage_pct')::numeric,0) >= 70 then 'Strong court coverage'
                   when coalesce((v_m->>'net_win_pct')::numeric,0)  >= 60 then 'Good control at the net'
                   else 'Creating attacking opportunities from the rear court' end;
    v_hold := coalesce(v_coach->0->>'title', 'Consistency under pressure');
    v_opp  := coalesce(v_coach->0->>'drill', 'Keep recovering to base after every shot to stay in position.');
    v_score := greatest(0, least(100, round((
                 coalesce((v_m->>'coverage_pct')::numeric,50) + coalesce((v_m->>'split_step_pct')::numeric,50) +
                 coalesce((v_m->>'net_win_pct')::numeric,50) + coalesce((v_m->>'landing_score')::numeric,50) +
                 (100 - coalesce((v_m->>'recovery_s')::numeric,1.2) * 40)) / 5)))::int;
    insert into public.analysis_reports (video_id, tag_id, lens, content, generated_by, is_mock, run_id) values
      (p_video_id, r.tag_id, 'coach', jsonb_build_object(
          'summary', case when p_is_mock then 'Sample coaching analysis (mock data for testing).'
                          else 'Coaching analysis from your match video.' end,
          'well', v_well, 'holding_back', v_hold, 'opportunity', v_opp, 'findings', v_coach), v_by, p_is_mock, p_run_id),
      (p_video_id, r.tag_id, 'physio', jsonb_build_object(
          'disclaimer','Automated movement-safety screen, not a medical diagnosis. See a physiotherapist for pain or injury.',
          'findings', public.match_rubric('physio', v_m)), v_by, p_is_mock, p_run_id),
      (p_video_id, r.tag_id, 'player', jsonb_build_object('score', v_score, 'focus', v_hold,
          'highlights', jsonb_build_array('Coverage ' || (v_m->>'coverage_pct') || '%',
                                          'Recovery ' || (v_m->>'recovery_s') || 's',
                                          'Split-step ' || (v_m->>'split_step_pct') || '%')), v_by, p_is_mock, p_run_id)
    on conflict (run_id, tag_id, lens) do update
      set content = excluded.content, is_mock = excluded.is_mock, generated_by = excluded.generated_by;
  end loop;
end;
$$;

drop function if exists public.finalize_analysis(uuid);
create or replace function public.finalize_analysis(p_video_id uuid, p_run_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_run uuid := public._run_or_latest(p_video_id, 'simple', p_run_id);
begin
  if v_run is null then v_run := public.start_analysis_run(p_video_id, 'simple', false, 'pose'); end if;
  update public.player_metrics set run_id = v_run where video_id = p_video_id and run_id is null;
  perform public.build_player_reports(p_video_id, false, v_run);
  update public.analysis_runs set status = 'done', error = null, finished_at = now() where id = v_run;
  update public.match_videos set status = 'done', analyzed_at = now(), is_mock = false, error = null where id = p_video_id;
end;
$$;

drop function if exists public.fail_analysis(uuid, text);
create or replace function public.fail_analysis(p_video_id uuid, p_error text, p_run_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_run uuid := public._run_or_latest(p_video_id, 'simple', p_run_id);
begin
  update public.analysis_runs set status = 'failed', error = left(coalesce(p_error,'analysis failed'), 500), finished_at = now()
   where id = v_run;
  update public.match_videos set status = 'failed', error = left(coalesce(p_error,'analysis failed'), 500) where id = p_video_id;
end;
$$;

drop function if exists public.finalize_deep(uuid);
create or replace function public.finalize_deep(p_video_id uuid, p_run_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_run uuid := public._run_or_latest(p_video_id, 'deep', p_run_id);
begin
  update public.analysis_runs set status = 'done', error = null, finished_at = now() where id = v_run;
  update public.match_videos set deep_status = 'done', is_deep_mock = false, deep_error = null where id = p_video_id;
end;
$$;

drop function if exists public.fail_deep(uuid, text);
create or replace function public.fail_deep(p_video_id uuid, p_error text, p_run_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_run uuid := public._run_or_latest(p_video_id, 'deep', p_run_id);
begin
  update public.analysis_runs set status = 'failed', error = left(coalesce(p_error,'deep analysis failed'), 500), finished_at = now()
   where id = v_run;
  update public.match_videos set deep_status = 'failed', deep_error = left(coalesce(p_error,'deep analysis failed'), 500)
   where id = p_video_id;
end;
$$;

-- 6. Mock seeders now create a new version too ----------------------------------------------------
create or replace function public.seed_mock_analysis(p_video_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_game text; v_n int; i int; v_track uuid; v_tag uuid; v_run uuid; v_metrics jsonb; v_side text; v_has_tags boolean;
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  select coalesce(game_type, 'singles') into v_game from public.match_videos where id = p_video_id;
  v_n := case when v_game = 'doubles' then 4 else 2 end;
  select exists(select 1 from public.video_player_tags where video_id = p_video_id) into v_has_tags;
  if not v_has_tags then
    for i in 1..v_n loop
      v_side := case when v_game = 'doubles' then (array['near_left','near_right','far_left','far_right'])[i]
                     else (array['near','far'])[i] end;
      insert into public.video_person_tracks (video_id, track_label, court_side, confidence, is_mock, first_seen_s, last_seen_s)
        values (p_video_id, 'P'||i, v_side, 0.7, true, 0, 60) returning id into v_track;
      insert into public.video_player_tags (video_id, track_id, label, court_side, is_subject)
        values (p_video_id, v_track, 'Player '||i, v_side, true);
    end loop;
  end if;
  v_run := public.start_analysis_run(p_video_id, 'simple', true, 'mock');
  for v_tag in select id from public.video_player_tags where video_id = p_video_id loop
    v_metrics := jsonb_build_object(
      'coverage_pct', 45 + floor(random()*45), 'recovery_s', round((0.9 + random()*1.2)::numeric, 2),
      'split_step_pct', 40 + floor(random()*55), 'net_win_pct', 30 + floor(random()*60),
      'landing_score', 40 + floor(random()*55), 'lunge_depth_risk', 30 + floor(random()*60),
      'backcourt_overreach', 30 + floor(random()*60),
      'shot_mix', jsonb_build_object('clear',30,'drop',22,'smash',18,'net',20,'drive',10));
    insert into public.player_metrics (video_id, tag_id, metrics, confidence, is_mock, run_id)
      values (p_video_id, v_tag, v_metrics,
        jsonb_build_object('coverage_pct',0.7,'recovery_s',0.65,'split_step_pct',0.6,'net_win_pct',0.55,
                           'landing_score',0.6,'_note','estimated from mock data'), true, v_run);
  end loop;
  perform public.build_player_reports(p_video_id, true, v_run);
  update public.analysis_runs set status = 'done', finished_at = now() where id = v_run;
  update public.match_videos set status = 'done', analyzed_at = now(), is_mock = true,
         tag_status = case when v_has_tags then tag_status else 'tagged' end where id = p_video_id;
end;
$$;

create or replace function public.seed_mock_deep(p_video_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tag uuid; v_dur numeric; i int; v_t numeric; v_type text; v_sev text; v_txt text; v_shot uuid; n int; v_run uuid;
  types text[] := array['overhead','drive','low'];
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  select coalesce(duration_s, 120) into v_dur from public.match_videos where id = p_video_id;
  v_run := public.start_analysis_run(p_video_id, 'deep', true, 'mock');
  for v_tag in select id from public.video_player_tags where video_id = p_video_id and is_subject loop
    n := 6 + floor(random()*6);
    for i in 1..n loop
      v_t := round((v_dur * i / (n + 1))::numeric, 1);
      v_type := types[1 + floor(random()*array_length(types,1))];
      v_sev := (array['good','info','watch','warning'])[1 + floor(random()*4)];
      insert into public.analysis_shots (video_id, tag_id, idx, t_s, shot_type, confidence, technique, is_mock, run_id)
        values (p_video_id, v_tag, i, v_t, v_type, 0.4,
                jsonb_build_object('contact', v_type, 'elbow_up', (random() > 0.5)), true, v_run)
        returning id into v_shot;
      v_txt := case v_type
        when 'overhead' then 'Sample: overhead stroke — prepare earlier and take the shuttle in front of your body.'
        when 'drive'    then 'Sample: flat drive — keep the racket up and push through the shuttle.'
        else 'Sample: low stroke near the net — get lower earlier and lift deep to a back corner.' end;
      insert into public.analysis_commentary (video_id, tag_id, shot_id, t_s, lens, text, severity, is_mock, run_id)
        values (p_video_id, v_tag, v_shot, v_t, 'coach', v_txt, v_sev, true, v_run);
    end loop;
  end loop;
  update public.analysis_runs set status = 'done', finished_at = now() where id = v_run;
  update public.match_videos set deep_status = 'done', is_deep_mock = true, deep_error = null where id = p_video_id;
end;
$$;

-- 7. Readers: return the list of versions + the selected version's data ---------------------------
drop function if exists public.get_video_analysis(uuid);
create or replace function public.get_video_analysis(p_video_id uuid, p_run_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_run uuid;
begin
  if not public.can_access_video(p_video_id) then return null; end if;
  v_run := coalesce(p_run_id,
    (select id from public.analysis_runs where video_id = p_video_id and kind = 'simple' and status = 'done'
      order by version desc limit 1));
  return jsonb_build_object(
    'video',   (select to_jsonb(mv) from public.match_videos mv where mv.id = p_video_id),
    'tracks',  coalesce((select jsonb_agg(to_jsonb(t) order by t.track_label) from public.video_person_tracks t where t.video_id = p_video_id), '[]'::jsonb),
    'tags',    coalesce((select jsonb_agg(to_jsonb(g)) from public.video_player_tags g where g.video_id = p_video_id), '[]'::jsonb),
    'events',  coalesce((select jsonb_agg(to_jsonb(e) order by e.at_s) from public.video_court_events e where e.video_id = p_video_id), '[]'::jsonb),
    'runs',    coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'version', r.version, 'status', r.status,
                         'is_mock', r.is_mock, 'error', r.error, 'created_at', r.created_at, 'finished_at', r.finished_at)
                         order by r.version desc) from public.analysis_runs r where r.video_id = p_video_id and r.kind = 'simple'), '[]'::jsonb),
    'run_id',  v_run,
    'metrics', coalesce((select jsonb_agg(to_jsonb(m)) from public.player_metrics m where m.run_id = v_run), '[]'::jsonb),
    'reports', coalesce((select jsonb_agg(to_jsonb(r)) from public.analysis_reports r where r.run_id = v_run), '[]'::jsonb));
end;
$$;

drop function if exists public.get_deep_analysis(uuid);
create or replace function public.get_deep_analysis(p_video_id uuid, p_run_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_run uuid;
begin
  if not public.can_access_video(p_video_id) then return null; end if;
  v_run := coalesce(p_run_id,
    (select id from public.analysis_runs where video_id = p_video_id and kind = 'deep' and status = 'done'
      order by version desc limit 1));
  return jsonb_build_object(
    'video',      (select to_jsonb(mv) from public.match_videos mv where mv.id = p_video_id),
    'tags',       coalesce((select jsonb_agg(to_jsonb(g)) from public.video_player_tags g where g.video_id = p_video_id), '[]'::jsonb),
    'runs',       coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'version', r.version, 'status', r.status,
                            'is_mock', r.is_mock, 'error', r.error, 'created_at', r.created_at, 'finished_at', r.finished_at)
                            order by r.version desc) from public.analysis_runs r where r.video_id = p_video_id and r.kind = 'deep'), '[]'::jsonb),
    'run_id',     v_run,
    'shots',      coalesce((select jsonb_agg(to_jsonb(s) order by s.t_s) from public.analysis_shots s where s.run_id = v_run), '[]'::jsonb),
    'commentary', coalesce((select jsonb_agg(to_jsonb(c) order by c.t_s) from public.analysis_commentary c where c.run_id = v_run), '[]'::jsonb));
end;
$$;

-- 8. Grants -----------------------------------------------------------------------------------------
-- Service-only: the worker / edge functions call these; regular users must not.
revoke execute on function public.start_analysis_run(uuid, text, boolean, text) from public, anon, authenticated;
revoke execute on function public._run_or_latest(uuid, text, uuid)              from public, anon, authenticated;
revoke execute on function public.build_player_reports(uuid, boolean, uuid)     from public, anon, authenticated;
revoke execute on function public.finalize_analysis(uuid, uuid)                  from public, anon, authenticated;
revoke execute on function public.fail_analysis(uuid, text, uuid)                from public, anon, authenticated;
revoke execute on function public.finalize_deep(uuid, uuid)                      from public, anon, authenticated;
revoke execute on function public.fail_deep(uuid, text, uuid)                    from public, anon, authenticated;
grant  execute on function public.start_analysis_run(uuid, text, boolean, text) to service_role;
grant  execute on function public._run_or_latest(uuid, text, uuid)              to service_role;
grant  execute on function public.build_player_reports(uuid, boolean, uuid)     to service_role;
grant  execute on function public.finalize_analysis(uuid, uuid)                  to service_role;
grant  execute on function public.fail_analysis(uuid, text, uuid)                to service_role;
grant  execute on function public.finalize_deep(uuid, uuid)                      to service_role;
grant  execute on function public.fail_deep(uuid, text, uuid)                    to service_role;
grant  execute on function public.get_video_analysis(uuid, uuid)                 to authenticated;
grant  execute on function public.get_deep_analysis(uuid, uuid)                  to authenticated;
grant  execute on function public.seed_mock_analysis(uuid)                       to authenticated;
grant  execute on function public.seed_mock_deep(uuid)                           to authenticated;
