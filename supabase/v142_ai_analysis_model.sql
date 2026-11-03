-- v142: AI Match Analysis — Phase A data model (no GPU).
-- Person tracks, player tagging, court-swap events, quantitative metrics, 3-lens reports
-- (coach / physio / player), analysis chat, and the rubric rules that drive coach + physio advice.
-- The Phase B Modal worker writes into video_person_tracks / player_metrics / analysis_reports
-- via the service role; everything here is RLS-scoped to the video's club.
-- Applied to project bdmiirppiyopmdfrztoz via MCP.

-- 0. Extend match_videos ---------------------------------------------------------------
alter table public.match_videos
  add column if not exists source          text not null default 'record'
      check (source in ('record','upload')),
  add column if not exists consent_version text,
  add column if not exists tag_status      text not null default 'pending'
      check (tag_status in ('pending','tagged','skipped')),
  add column if not exists analyzed_at      timestamptz,
  add column if not exists error            text,
  add column if not exists is_mock          boolean not null default false;

-- Access helpers (SECURITY DEFINER so they resolve the video's club past RLS) -----------
create or replace function public.can_access_video(p_video_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.match_videos mv
    where mv.id = p_video_id
      and (public.is_member(mv.club_id) or mv.uploaded_by = auth.uid() or public.is_app_admin())
  );
$$;

create or replace function public.can_manage_video(p_video_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.match_videos mv
    where mv.id = p_video_id
      and (mv.uploaded_by = auth.uid() or public.is_manager(mv.club_id) or public.is_app_admin())
  );
$$;

-- 1. Person tracks (one per detected person on court) -----------------------------------
create table if not exists public.video_person_tracks (
  id           uuid primary key default gen_random_uuid(),
  video_id     uuid not null references public.match_videos(id) on delete cascade,
  track_label  text not null,                 -- 'P1','P2'...
  thumb_path   text,                           -- R2 key of a crop (optional)
  first_seen_s numeric,
  last_seen_s  numeric,
  court_side   text,                           -- near|far|near_left|near_right|far_left|far_right
  confidence   numeric,
  is_mock      boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists idx_vpt_video on public.video_person_tracks(video_id);
alter table public.video_person_tracks enable row level security;
drop policy if exists vpt_sel on public.video_person_tracks;
drop policy if exists vpt_ins on public.video_person_tracks;
drop policy if exists vpt_upd on public.video_person_tracks;
drop policy if exists vpt_del on public.video_person_tracks;
create policy vpt_sel on public.video_person_tracks for select using (public.can_access_video(video_id));
create policy vpt_ins on public.video_person_tracks for insert with check (public.can_manage_video(video_id));
create policy vpt_upd on public.video_person_tracks for update using (public.can_manage_video(video_id));
create policy vpt_del on public.video_person_tracks for delete using (public.can_manage_video(video_id));

-- 2. Player tags (map a track -> a roster player or a placeholder like 'Opponent A') -----
create table if not exists public.video_player_tags (
  id          uuid primary key default gen_random_uuid(),
  video_id    uuid not null references public.match_videos(id) on delete cascade,
  track_id    uuid references public.video_person_tracks(id) on delete set null,
  player_id   uuid references public.players(id) on delete set null,
  label       text,                            -- non-roster name ('Opponent A')
  court_side  text,
  is_subject  boolean not null default false,  -- a person we produce a full report for
  assigned_by uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  unique (video_id, track_id)
);
create index if not exists idx_vptag_video on public.video_player_tags(video_id);
alter table public.video_player_tags enable row level security;
drop policy if exists vptag_sel on public.video_player_tags;
drop policy if exists vptag_ins on public.video_player_tags;
drop policy if exists vptag_upd on public.video_player_tags;
drop policy if exists vptag_del on public.video_player_tags;
create policy vptag_sel on public.video_player_tags for select using (public.can_access_video(video_id));
create policy vptag_ins on public.video_player_tags for insert with check (public.can_manage_video(video_id));
create policy vptag_upd on public.video_player_tags for update using (public.can_manage_video(video_id));
create policy vptag_del on public.video_player_tags for delete using (public.can_manage_video(video_id));

-- 3. Court events (ends swapped mid-match) ----------------------------------------------
create table if not exists public.video_court_events (
  id         uuid primary key default gen_random_uuid(),
  video_id   uuid not null references public.match_videos(id) on delete cascade,
  event_type text not null default 'end_swap' check (event_type in ('end_swap')),
  at_s       numeric not null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists idx_vce_video on public.video_court_events(video_id);
alter table public.video_court_events enable row level security;
drop policy if exists vce_sel on public.video_court_events;
drop policy if exists vce_ins on public.video_court_events;
drop policy if exists vce_del on public.video_court_events;
create policy vce_sel on public.video_court_events for select using (public.can_access_video(video_id));
create policy vce_ins on public.video_court_events for insert with check (public.can_manage_video(video_id));
create policy vce_del on public.video_court_events for delete using (public.can_manage_video(video_id));

-- 4. Rallies (optional richness; worker fills) ------------------------------------------
create table if not exists public.analysis_rallies (
  id            uuid primary key default gen_random_uuid(),
  video_id      uuid not null references public.match_videos(id) on delete cascade,
  idx           integer,
  start_s       numeric,
  end_s         numeric,
  shots         integer,
  winner_tag_id uuid references public.video_player_tags(id) on delete set null,
  summary       jsonb not null default '{}',
  is_mock       boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists idx_rally_video on public.analysis_rallies(video_id);
alter table public.analysis_rallies enable row level security;
drop policy if exists rally_sel on public.analysis_rallies;
drop policy if exists rally_wr on public.analysis_rallies;
create policy rally_sel on public.analysis_rallies for select using (public.can_access_video(video_id));
create policy rally_wr  on public.analysis_rallies for all   using (public.can_manage_video(video_id)) with check (public.can_manage_video(video_id));

-- 5. Quantitative metrics (one row per tagged person) -----------------------------------
create table if not exists public.player_metrics (
  id         uuid primary key default gen_random_uuid(),
  video_id   uuid not null references public.match_videos(id) on delete cascade,
  tag_id     uuid not null references public.video_player_tags(id) on delete cascade,
  metrics    jsonb not null default '{}',     -- coverage_pct, recovery_s, split_step_pct, shot_mix{}, landing_score...
  confidence jsonb not null default '{}',     -- per-metric 0..1 confidence (whitepaper: never silently guess)
  is_mock    boolean not null default false,
  created_at timestamptz not null default now(),
  unique (video_id, tag_id)
);
create index if not exists idx_pm_video on public.player_metrics(video_id);
alter table public.player_metrics enable row level security;
drop policy if exists pm_sel on public.player_metrics;
drop policy if exists pm_wr on public.player_metrics;
create policy pm_sel on public.player_metrics for select using (public.can_access_video(video_id));
create policy pm_wr  on public.player_metrics for all   using (public.can_manage_video(video_id)) with check (public.can_manage_video(video_id));

-- 6. Reports — one row per (person, lens): coach | physio | player ----------------------
create table if not exists public.analysis_reports (
  id           uuid primary key default gen_random_uuid(),
  video_id     uuid not null references public.match_videos(id) on delete cascade,
  tag_id       uuid not null references public.video_player_tags(id) on delete cascade,
  lens         text not null check (lens in ('coach','physio','player')),
  content      jsonb not null default '{}',
  generated_by text,
  is_mock      boolean not null default false,
  created_at   timestamptz not null default now(),
  unique (video_id, tag_id, lens)
);
create index if not exists idx_ar_video on public.analysis_reports(video_id);
alter table public.analysis_reports enable row level security;
drop policy if exists ar_sel on public.analysis_reports;
drop policy if exists ar_wr on public.analysis_reports;
create policy ar_sel on public.analysis_reports for select using (public.can_access_video(video_id));
create policy ar_wr  on public.analysis_reports for all   using (public.can_manage_video(video_id)) with check (public.can_manage_video(video_id));

-- 7. Analysis chat (ask about your own performance) -------------------------------------
create table if not exists public.analysis_chat_threads (
  id         uuid primary key default gen_random_uuid(),
  video_id   uuid not null references public.match_videos(id) on delete cascade,
  tag_id     uuid references public.video_player_tags(id) on delete set null,
  user_id    uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);
create table if not exists public.analysis_chat_messages (
  id         uuid primary key default gen_random_uuid(),
  thread_id  uuid not null references public.analysis_chat_threads(id) on delete cascade,
  role       text not null check (role in ('user','assistant')),
  content    text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_act_video on public.analysis_chat_threads(video_id);
create index if not exists idx_acm_thread on public.analysis_chat_messages(thread_id);
alter table public.analysis_chat_threads  enable row level security;
alter table public.analysis_chat_messages enable row level security;
drop policy if exists act_sel on public.analysis_chat_threads;
drop policy if exists act_ins on public.analysis_chat_threads;
create policy act_sel on public.analysis_chat_threads for select
  using (user_id = auth.uid() and public.can_access_video(video_id));
create policy act_ins on public.analysis_chat_threads for insert
  with check (user_id = auth.uid() and public.can_access_video(video_id));
drop policy if exists acm_sel on public.analysis_chat_messages;
drop policy if exists acm_ins on public.analysis_chat_messages;
create policy acm_sel on public.analysis_chat_messages for select
  using (exists (select 1 from public.analysis_chat_threads t where t.id = thread_id and t.user_id = auth.uid()));
create policy acm_ins on public.analysis_chat_messages for insert
  with check (exists (select 1 from public.analysis_chat_threads t where t.id = thread_id and t.user_id = auth.uid()));

-- 8. Rubric — best-practice rules that turn metrics into coach/physio advice -------------
create table if not exists public.analysis_rubric (
  id         uuid primary key default gen_random_uuid(),
  lens       text not null check (lens in ('coach','physio')),
  code       text unique not null,
  metric_key text not null,
  comparator text not null check (comparator in ('lt','lte','gt','gte','between')),
  threshold  numeric,
  threshold2 numeric,
  severity   text not null default 'info' check (severity in ('info','watch','warning')),
  title      text not null,
  message    text not null,
  drill      text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.analysis_rubric enable row level security;
drop policy if exists rub_sel on public.analysis_rubric;
drop policy if exists rub_wr on public.analysis_rubric;
create policy rub_sel on public.analysis_rubric for select using (auth.uid() is not null);
create policy rub_wr  on public.analysis_rubric for all using (public.is_app_admin()) with check (public.is_app_admin());

insert into public.analysis_rubric (lens, code, metric_key, comparator, threshold, severity, title, message, drill) values
  ('coach','cov_low','coverage_pct','lt',55,'watch','Court coverage',
   'You are covering less of the court than ideal, leaving gaps an opponent can exploit.',
   'Shadow footwork: 6-corner movement, 3×30s, returning to base each time.'),
  ('coach','recovery_slow','recovery_s','gt',1.4,'watch','Recovery to base',
   'Your return to a central base after a shot is slow, so you are often out of position for the next reply.',
   'Base-return drill: feed to corners, sprint back to centre with a split-step before each feed.'),
  ('coach','split_low','split_step_pct','lt',60,'watch','Split-step timing',
   'You are not split-stepping on enough shots, which delays your first step.',
   'Split-step on every feed: 2×1 min multi-shuttle, land the split as the feeder contacts the shuttle.'),
  ('coach','net_weak','net_win_pct','lt',40,'info','Net play',
   'You win fewer net exchanges than baseline — tightening net shots will create more openings.',
   'Net-tight drill: 3×20 cross-court and straight net shots aiming inside the service line.'),
  ('physio','landing_risk','landing_score','lt',55,'warning','Jump-landing mechanics',
   'Your jump landings show knee collapse / stiff landing patterns that raise knee-injury risk over time. This is not a medical diagnosis — see a physiotherapist if you have pain.',
   'Landing drills: box drops with soft knee-over-toe landing, 3×8, hips back and knees tracking out.'),
  ('physio','lunge_risk','lunge_depth_risk','gt',60,'warning','Forward lunge load',
   'Deep, hard forward lunges with the knee past the toe repeatedly load the knee and patellar tendon. Not a diagnosis — consult a professional if painful.',
   'Controlled lunge strength: tempo split-squats 3×8 each leg, plus calf raises for shock absorption.'),
  ('physio','overreach_back','backcourt_overreach','gt',60,'watch','Backward movement',
   'Frequent off-balance backward reaching stresses the shoulder and lower back and risks falls. Not a diagnosis.',
   'Scissor-jump footwork to the rear court, landing balanced; core anti-extension work (dead-bugs 3×10).')
on conflict (code) do nothing;

-- 9. RPCs --------------------------------------------------------------------------------

-- Replace the tag set for a video (tap-to-name result).
create or replace function public.set_video_tags(p_video_id uuid, p_tags jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  delete from public.video_player_tags where video_id = p_video_id;
  insert into public.video_player_tags (video_id, track_id, player_id, label, court_side, is_subject)
  select p_video_id,
         nullif(t->>'track_id','')::uuid,
         nullif(t->>'player_id','')::uuid,
         nullif(t->>'label',''),
         nullif(t->>'court_side',''),
         coalesce((t->>'is_subject')::boolean, false)
  from jsonb_array_elements(coalesce(p_tags, '[]'::jsonb)) t;
  update public.match_videos set tag_status = 'tagged' where id = p_video_id;
end;
$$;

create or replace function public.add_court_event(p_video_id uuid, p_at_s numeric, p_type text default 'end_swap')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  insert into public.video_court_events (video_id, event_type, at_s)
  values (p_video_id, p_type, p_at_s) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.remove_court_event(p_event_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.video_court_events e
   where e.id = p_event_id and public.can_manage_video(e.video_id);
end;
$$;

-- Everything the report UI needs in one call.
create or replace function public.get_video_analysis(p_video_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not public.can_access_video(p_video_id) then null else
    jsonb_build_object(
      'video',   (select to_jsonb(mv) from public.match_videos mv where mv.id = p_video_id),
      'tracks',  coalesce((select jsonb_agg(to_jsonb(t) order by t.track_label) from public.video_person_tracks t where t.video_id = p_video_id), '[]'::jsonb),
      'tags',    coalesce((select jsonb_agg(to_jsonb(g)) from public.video_player_tags g where g.video_id = p_video_id), '[]'::jsonb),
      'events',  coalesce((select jsonb_agg(to_jsonb(e) order by e.at_s) from public.video_court_events e where e.video_id = p_video_id), '[]'::jsonb),
      'metrics', coalesce((select jsonb_agg(to_jsonb(m)) from public.player_metrics m where m.video_id = p_video_id), '[]'::jsonb),
      'reports', coalesce((select jsonb_agg(to_jsonb(r)) from public.analysis_reports r where r.video_id = p_video_id), '[]'::jsonb)
    ) end;
$$;

-- Mark a video for analysis (Phase B Modal worker picks it up). Phase A has no worker yet.
create or replace function public.request_video_analysis(p_video_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  update public.match_videos set status = 'analyzing', error = null where id = p_video_id;
end;
$$;

grant execute on function public.set_video_tags(uuid, jsonb)        to authenticated;
grant execute on function public.add_court_event(uuid, numeric, text) to authenticated;
grant execute on function public.remove_court_event(uuid)           to authenticated;
grant execute on function public.get_video_analysis(uuid)           to authenticated;
grant execute on function public.request_video_analysis(uuid)       to authenticated;
