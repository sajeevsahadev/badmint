-- v151 (+v151b): opt-in face recognition for match-video tagging. Applied via MCP 2026-11-08.
-- Biometric data (GDPR Art. 9): explicit per-person consent (user_profiles.face_id_consent), library
-- readable/deletable only by its owner, withdrawing consent deletes everything at once,
-- face_library cascades on account deletion. Per-video signatures (video_slot_faces) are service-only and
-- purged for non-consenting players as soon as the video is tagged.
alter table public.user_profiles
  add column if not exists face_id_consent boolean not null default false,
  add column if not exists face_id_consent_at timestamptz;

create table if not exists public.face_library (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  embedding real[] not null,
  quality real,
  source_video_id uuid references public.match_videos(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists face_library_user_idx on public.face_library(user_id);
alter table public.face_library enable row level security;
drop policy if exists fl_own_sel on public.face_library;
drop policy if exists fl_own_del on public.face_library;
create policy fl_own_sel on public.face_library for select using (user_id = auth.uid());
create policy fl_own_del on public.face_library for delete using (user_id = auth.uid());

create table if not exists public.video_slot_faces (
  video_id uuid not null references public.match_videos(id) on delete cascade,
  court_side text not null,
  embedding real[] not null,
  quality real,
  n_faces int,
  created_at timestamptz not null default now(),
  primary key (video_id, court_side)
);
alter table public.video_slot_faces enable row level security;

create or replace function public._face_sim(a real[], b real[])
returns real language sql immutable as $$
  select coalesce(sum(x*y), 0)::real from unnest(a, b) as t(x, y)
$$;

create or replace function public.set_face_id_consent(p_on boolean)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update user_profiles set face_id_consent = p_on,
         face_id_consent_at = case when p_on then now() else null end
   where user_id = auth.uid();
  if not found then raise exception 'Complete your profile first'; end if;
  if not p_on then delete from face_library where user_id = auth.uid(); end if;
  return p_on;
end $$;

create or replace function public.get_face_id_status()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'consent', coalesce((select face_id_consent from user_profiles where user_id = auth.uid()), false),
    'since',   (select face_id_consent_at from user_profiles where user_id = auth.uid()),
    'samples', (select count(*) from face_library where user_id = auth.uid()))
$$;

create or replace function public.enroll_video_faces(p_video_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; v_known int; v_best real;
begin
  if auth.role() <> 'service_role' and not public.can_manage_video(p_video_id) then
    raise exception 'Not allowed';
  end if;
  for r in
    select f.court_side, f.embedding, f.quality, p.user_id
      from video_slot_faces f
      join video_player_tags t on t.video_id = f.video_id and t.court_side = f.court_side
      join players p on p.id = t.player_id
      join user_profiles up on up.user_id = p.user_id and up.face_id_consent
     where f.video_id = p_video_id and f.n_faces >= 2
  loop
    select count(*), max(public._face_sim(embedding, r.embedding)) into v_known, v_best
      from face_library where user_id = r.user_id;
    if v_known >= 2 and v_best < 0.30 then continue; end if;   -- disagrees with what we hold: likely a wrong tag
    delete from face_library where user_id = r.user_id and source_video_id = p_video_id;
    insert into face_library (user_id, embedding, quality, source_video_id)
      values (r.user_id, r.embedding, r.quality, p_video_id);
    delete from face_library where id in (
      select id from face_library where user_id = r.user_id order by created_at desc offset 10);
    n := n + 1;
  end loop;
  if exists (select 1 from match_videos where id = p_video_id and tag_status = 'tagged') then
    delete from video_slot_faces f where f.video_id = p_video_id and not exists (
      select 1 from video_player_tags t join players p on p.id = t.player_id
        join user_profiles up on up.user_id = p.user_id and up.face_id_consent
       where t.video_id = f.video_id and t.court_side = f.court_side);
  end if;
  return n;
end $$;

create or replace function public.suggest_video_tags(p_video_id uuid)
returns table(court_side text, player_id uuid, score real, confident boolean)
language plpgsql security definer set search_path = public as $$
declare v_club uuid; r record; used_s text[] := '{}'; used_p uuid[] := '{}';
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  select club_id into v_club from match_videos where id = p_video_id;
  for r in
    select f.court_side cs, p.id pid, max(public._face_sim(l.embedding, f.embedding)) sim
      from video_slot_faces f
      cross join players p
      join user_profiles up on up.user_id = p.user_id and up.face_id_consent
      join face_library l on l.user_id = p.user_id
     where f.video_id = p_video_id and p.club_id = v_club and p.is_active
     group by f.court_side, p.id
     order by sim desc
  loop
    exit when r.sim < 0.40;
    if r.cs = any(used_s) or r.pid = any(used_p) then continue; end if;
    used_s := used_s || r.cs; used_p := used_p || r.pid;
    court_side := r.cs; player_id := r.pid; score := r.sim; confident := r.sim >= 0.50;
    return next;
  end loop;
end $$;

grant execute on function public.set_face_id_consent(boolean) to authenticated;
grant execute on function public.get_face_id_status() to authenticated;
grant execute on function public.suggest_video_tags(uuid) to authenticated;
grant execute on function public.enroll_video_faces(uuid) to authenticated, service_role;
revoke execute on function public._face_sim(real[], real[]) from anon;

-- v151b: set_video_tags now ends with:  perform public.enroll_video_faces(p_video_id);
-- v151c: suggest_video_tags tightened — sim >= 0.45 (confident >= 0.55) AND at least 0.10 ahead of the
--        runner-up for that slot and for that person in other slots; otherwise left for a human.
