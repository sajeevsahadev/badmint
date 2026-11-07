-- v149: AI Match Analysis — Head Coach Summary (premium).
-- One row per (analysis version, player): measured KPIs, the coach's verdict (strengths / focus / drills)
-- and its voice clip. Progress across matches is read from these rows over time.
--   * motion  — written by the Modal worker (distance covered, tracked seconds)
--   * kpis    — computed by generate-commentary from analysis_shots (counts + rates)
--   * coach   — Gemini "head coach" verdict grounded in kpis + the player's previous match
-- Reads go through SECURITY DEFINER RPCs that check club access AND premium (early access today).

create table if not exists public.analysis_player_summary (
  id          uuid primary key default gen_random_uuid(),
  video_id    uuid not null references public.match_videos(id) on delete cascade,
  run_id      uuid not null references public.analysis_runs(id) on delete cascade,
  tag_id      uuid not null references public.video_player_tags(id) on delete cascade,
  player_id   uuid references public.players(id) on delete set null,
  motion      jsonb not null default '{}'::jsonb,
  kpis        jsonb not null default '{}'::jsonb,
  coach       jsonb,
  audio_path  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (run_id, tag_id)
);
create index if not exists aps_player_idx on public.analysis_player_summary(player_id, created_at);
create index if not exists aps_video_idx  on public.analysis_player_summary(video_id);

alter table public.analysis_player_summary enable row level security;
-- No client policies: service role writes, RPCs read.
revoke all on public.analysis_player_summary from anon, authenticated;

-- Fill player_id from the tag (tags may be linked to a roster player after the run).
create or replace function public.aps_fill_player() returns trigger language plpgsql as $$
begin
  if new.player_id is null then
    select player_id into new.player_id from public.video_player_tags where id = new.tag_id;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists aps_fill_player on public.analysis_player_summary;
create trigger aps_fill_player before insert or update on public.analysis_player_summary
  for each row execute function public.aps_fill_player();

-- Keep player_id in step when someone (re)links a tag to a player.
create or replace function public.vpt_sync_summary_player() returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if new.player_id is distinct from old.player_id then
    update public.analysis_player_summary set player_id = new.player_id where tag_id = new.id;
  end if;
  return new;
end $$;
drop trigger if exists vpt_sync_summary_player on public.video_player_tags;
create trigger vpt_sync_summary_player after update of player_id on public.video_player_tags
  for each row execute function public.vpt_sync_summary_player();

-- Can the caller see this video's analysis? (uploader, club member, or app admin)
create or replace function public._can_view_video(p_video_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.match_videos v where v.id = p_video_id and (
            v.uploaded_by = auth.uid() or public.is_member(v.club_id) or public.is_app_admin()));
$$;

-- Summaries for one deep version (default: the latest completed one) of a video.
create or replace function public.get_deep_summary(p_video_id uuid, p_run_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_run uuid;
begin
  if not public._can_view_video(p_video_id) then raise exception 'Not allowed'; end if;
  if not public.has_early_access() then return jsonb_build_object('locked', true); end if;
  v_run := coalesce(p_run_id, (select id from public.analysis_runs where video_id = p_video_id and kind = 'deep'
                                 and status = 'done' order by version desc limit 1));
  return jsonb_build_object('locked', false, 'run_id', v_run, 'players', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id, 'tag_id', s.tag_id, 'player_id', s.player_id,
      'name', coalesce(pl.display_name, t.label, 'Player'),
      'kpis', s.kpis, 'motion', s.motion, 'coach', s.coach, 'has_audio', s.audio_path is not null,
      -- the same player's previous analysed match (for "last time → this time")
      'previous', (select jsonb_build_object('kpis', p2.kpis, 'at', coalesce(v2.created_at, p2.created_at), 'video', v2.title)
                     from public.analysis_player_summary p2
                     join public.analysis_runs r2 on r2.id = p2.run_id and r2.status = 'done' and not r2.is_mock
                     join public.match_videos v2 on v2.id = p2.video_id
                    where s.player_id is not null and p2.player_id = s.player_id and p2.video_id <> s.video_id
                      and coalesce(v2.created_at, p2.created_at) < (select created_at from public.match_videos where id = s.video_id)
                      and p2.kpis ? 'strokes'
                    order by v2.created_at desc limit 1))
      order by t.is_subject desc, t.court_side)
    from public.analysis_player_summary s
    join public.video_player_tags t on t.id = s.tag_id
    left join public.players pl on pl.id = s.player_id
    where s.run_id = v_run and s.kpis ? 'strokes'), '[]'::jsonb));
end $$;

-- KPI history for one roster player — or, with no player, every player linked to the caller.
-- One point per video (its latest completed deep version), oldest first.
create or replace function public.get_player_ai_progress(p_player_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ids uuid[];
begin
  if not public.has_early_access() then return jsonb_build_object('locked', true); end if;
  if p_player_id is null then
    select array_agg(id) into v_ids from public.players where user_id = auth.uid();
  else
    if not exists (select 1 from public.players p where p.id = p_player_id
                     and (p.user_id = auth.uid() or public.is_member(p.club_id) or public.is_app_admin())) then
      raise exception 'Not allowed';
    end if;
    v_ids := array[p_player_id];
  end if;
  return jsonb_build_object('locked', false, 'points', coalesce((
    select jsonb_agg(x order by x->>'at') from (
      select distinct on (s.video_id) jsonb_build_object(
          'video_id', s.video_id, 'run_id', s.run_id, 'video', v.title, 'club', c.name,
          'at', v.created_at, 'kpis', s.kpis, 'focus', s.coach->'focus', 'rating', s.coach->'rating') x
        from public.analysis_player_summary s
        join public.analysis_runs r on r.id = s.run_id and r.status = 'done' and not r.is_mock
        join public.match_videos v on v.id = s.video_id
        left join public.clubs c on c.id = v.club_id
       where s.player_id = any(v_ids) and s.kpis ? 'strokes'
       order by s.video_id, r.version desc) q), '[]'::jsonb));
end $$;

revoke all on function public.get_deep_summary(uuid, uuid), public.get_player_ai_progress(uuid),
                       public._can_view_video(uuid) from public, anon;
grant execute on function public.get_deep_summary(uuid, uuid), public.get_player_ai_progress(uuid) to authenticated;
