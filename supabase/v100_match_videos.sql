-- Phase 0 (AI Video Coaching): record & store match videos.
-- Storage stays in Supabase Storage for the prototype; swappable to Cloudflare R2 later.
-- Applied to project bdmiirppiyopmdfrztoz via MCP.

-- 1. Private bucket for match videos (500 MB/file, video types only).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('match-videos', 'match-videos', false, 524288000,
        array['video/webm','video/mp4','video/quicktime','video/x-matroska'])
on conflict (id) do update
  set file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 2. Metadata table. A video may be recorded before a match row exists, so match_id is nullable.
create table if not exists public.match_videos (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references public.clubs(id) on delete cascade,
  match_id     uuid references public.matches(id) on delete set null,
  uploaded_by  uuid not null references auth.users(id) default auth.uid(),
  title        text,
  game_type    text check (game_type in ('singles','doubles')),
  player_ids   uuid[] not null default '{}',        -- tagged players (from public.players)
  consent      boolean not null default false,       -- everyone on court consented to recording
  storage_path text,                                 -- key inside the match-videos bucket
  youtube_url  text,                                 -- optional offload target (later)
  status       text not null default 'uploaded'
               check (status in ('uploaded','analyzing','done','failed')),
  duration_s   integer,
  size_bytes   bigint,
  purge_at     timestamptz default (now() + interval '30 days'),
  created_at   timestamptz not null default now()
);
create index if not exists idx_match_videos_club  on public.match_videos(club_id);
create index if not exists idx_match_videos_match on public.match_videos(match_id);

alter table public.match_videos enable row level security;

drop policy if exists mv_select on public.match_videos;
create policy mv_select on public.match_videos for select
  using (public.is_member(club_id) or uploaded_by = auth.uid() or public.is_app_admin());

drop policy if exists mv_insert on public.match_videos;
create policy mv_insert on public.match_videos for insert
  with check (public.is_member(club_id) and uploaded_by = auth.uid());

drop policy if exists mv_update on public.match_videos;
create policy mv_update on public.match_videos for update
  using (uploaded_by = auth.uid() or public.is_manager(club_id) or public.is_app_admin());

drop policy if exists mv_delete on public.match_videos;
create policy mv_delete on public.match_videos for delete
  using (uploaded_by = auth.uid() or public.is_manager(club_id) or public.is_app_admin());

-- 3. Storage object policies. Path convention: "<club_id>/<video_id>.<ext>".
drop policy if exists mvobj_select on storage.objects;
create policy mvobj_select on storage.objects for select to authenticated
  using (bucket_id = 'match-videos'
         and public.is_member(((storage.foldername(name))[1])::uuid));

drop policy if exists mvobj_insert on storage.objects;
create policy mvobj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'match-videos'
              and public.is_member(((storage.foldername(name))[1])::uuid));

drop policy if exists mvobj_delete on storage.objects;
create policy mvobj_delete on storage.objects for delete to authenticated
  using (bucket_id = 'match-videos'
         and (public.is_manager(((storage.foldername(name))[1])::uuid) or public.is_app_admin()));
