-- v153: "Not a real shot" feedback on analysed strokes.
-- A person who can open the video marks a stroke the engine got wrong (shuttle picked up, passed
-- back, warm-up hit). The stroke is hidden from that report for everyone, and the row is kept by
-- video + court side + time so the next analysis of the same video skips it and the engine rules
-- can be tuned against real examples.

create table if not exists public.shot_feedback (
  id          uuid primary key default gen_random_uuid(),
  video_id    uuid not null references public.match_videos(id) on delete cascade,
  run_id      uuid,
  shot_id     uuid references public.analysis_shots(id) on delete set null,
  court_side  text,
  t_s         numeric not null,
  verdict     text not null default 'not_a_shot',
  engine      text,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists shot_feedback_video_idx on public.shot_feedback(video_id);
create unique index if not exists shot_feedback_shot_uq on public.shot_feedback(shot_id) where shot_id is not null;

alter table public.shot_feedback enable row level security;
drop policy if exists sfb_sel on public.shot_feedback;
create policy sfb_sel on public.shot_feedback for select using (public.can_access_video(video_id));
-- writes only through the RPCs below

create or replace function public.flag_shot(p_shot_id uuid)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare s record; v_id uuid;
begin
  select sh.id, sh.video_id, sh.run_id, sh.t_s, sh.meta->>'engine' as engine, t.court_side
    into s
  from public.analysis_shots sh left join public.video_player_tags t on t.id = sh.tag_id
  where sh.id = p_shot_id;
  if not found then raise exception 'Stroke not found'; end if;
  if not public.can_access_video(s.video_id) then raise exception 'Not allowed'; end if;
  select id into v_id from public.shot_feedback where shot_id = p_shot_id;
  if v_id is not null then return v_id; end if;
  insert into public.shot_feedback (video_id, run_id, shot_id, court_side, t_s, engine, created_by)
  values (s.video_id, s.run_id, s.id, s.court_side, s.t_s, s.engine, auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.unflag_shot(p_shot_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_video uuid;
begin
  select video_id into v_video from public.shot_feedback where shot_id = p_shot_id;
  if v_video is null then return; end if;
  if not public.can_access_video(v_video) then raise exception 'Not allowed'; end if;
  delete from public.shot_feedback where shot_id = p_shot_id;
end $$;

revoke all on function public.flag_shot(uuid) from public, anon;
revoke all on function public.unflag_shot(uuid) from public, anon;
grant execute on function public.flag_shot(uuid) to authenticated;
grant execute on function public.unflag_shot(uuid) to authenticated;
