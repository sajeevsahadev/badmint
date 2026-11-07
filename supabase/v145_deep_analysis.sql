-- v145: Deep Analysis (premium tier) — shot-by-shot timeline + coach/physio commentary.
-- The Modal worker detects shots (pose) and writes analysis_shots; the generate-commentary Edge
-- Function turns the shot timeline into natural per-shot commentary (analysis_commentary), like
-- cricket ball-by-ball. Simple tier (player_metrics / analysis_reports) is unchanged.
-- Applied to project bdmiirppiyopmdfrztoz via MCP.

alter table public.match_videos
  add column if not exists deep_status       text not null default 'none'
      check (deep_status in ('none','analyzing','done','failed')),
  add column if not exists deep_error        text,
  add column if not exists deep_requested_at timestamptz,
  add column if not exists is_deep_mock      boolean not null default false;

-- One row per detected shot/hit.
create table if not exists public.analysis_shots (
  id         uuid primary key default gen_random_uuid(),
  video_id   uuid not null references public.match_videos(id) on delete cascade,
  tag_id     uuid references public.video_player_tags(id) on delete set null,
  idx        integer,
  t_s        numeric not null,                 -- timestamp of the shot (seconds)
  shot_type  text,                             -- clear|drop|smash|net|drive|lift|serve|unknown
  confidence numeric,
  zone       text,                             -- placement zone (phase 2, nullable)
  technique  jsonb not null default '{}',      -- {contact_height, in_front, elbow_up, ...}
  meta       jsonb not null default '{}',
  is_mock    boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_shots_video on public.analysis_shots(video_id);
alter table public.analysis_shots enable row level security;
drop policy if exists shots_sel on public.analysis_shots;
drop policy if exists shots_wr on public.analysis_shots;
create policy shots_sel on public.analysis_shots for select using (public.can_access_video(video_id));
create policy shots_wr  on public.analysis_shots for all using (public.can_manage_video(video_id)) with check (public.can_manage_video(video_id));

-- One row per commentary line (ball-by-ball). Tied to a shot where applicable.
create table if not exists public.analysis_commentary (
  id         uuid primary key default gen_random_uuid(),
  video_id   uuid not null references public.match_videos(id) on delete cascade,
  tag_id     uuid references public.video_player_tags(id) on delete set null,
  shot_id    uuid references public.analysis_shots(id) on delete set null,
  t_s        numeric not null,
  lens       text not null default 'coach' check (lens in ('coach','physio')),
  text       text not null,
  severity   text not null default 'info' check (severity in ('good','info','watch','warning')),
  is_mock    boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_comm_video on public.analysis_commentary(video_id);
alter table public.analysis_commentary enable row level security;
drop policy if exists comm_sel on public.analysis_commentary;
drop policy if exists comm_wr on public.analysis_commentary;
create policy comm_sel on public.analysis_commentary for select using (public.can_access_video(video_id));
create policy comm_wr  on public.analysis_commentary for all using (public.can_manage_video(video_id)) with check (public.can_manage_video(video_id));

-- Everything the deep UI needs in one call.
create or replace function public.get_deep_analysis(p_video_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not public.can_access_video(p_video_id) then null else
    jsonb_build_object(
      'video',     (select to_jsonb(mv) from public.match_videos mv where mv.id = p_video_id),
      'tags',      coalesce((select jsonb_agg(to_jsonb(g)) from public.video_player_tags g where g.video_id = p_video_id), '[]'::jsonb),
      'shots',     coalesce((select jsonb_agg(to_jsonb(s) order by s.t_s) from public.analysis_shots s where s.video_id = p_video_id), '[]'::jsonb),
      'commentary',coalesce((select jsonb_agg(to_jsonb(c) order by c.t_s) from public.analysis_commentary c where c.video_id = p_video_id), '[]'::jsonb)
    ) end;
$$;

create or replace function public.request_deep_analysis(p_video_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  update public.match_videos set deep_status = 'analyzing', deep_error = null, deep_requested_at = now()
   where id = p_video_id;
end;
$$;

-- Service-role finalizers (worker / commentary function call these).
create or replace function public.finalize_deep(p_video_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.match_videos set deep_status = 'done', is_deep_mock = false, deep_error = null where id = p_video_id;
end;
$$;

create or replace function public.fail_deep(p_video_id uuid, p_error text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.match_videos set deep_status = 'failed', deep_error = left(coalesce(p_error,'deep analysis failed'), 500)
   where id = p_video_id;
end;
$$;

grant execute on function public.get_deep_analysis(uuid)      to authenticated;
grant execute on function public.request_deep_analysis(uuid)  to authenticated;
grant execute on function public.finalize_deep(uuid)          to service_role;
grant execute on function public.fail_deep(uuid, text)        to service_role;
