-- Phase 3: early-access waitlist. Users request access; admins approve (which grants the role).
-- Applied to bdmiirppiyopmdfrztoz via MCP.
create table if not exists public.early_access_requests (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text, note text,
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  created_at timestamptz not null default now(), decided_at timestamptz, decided_by uuid
);
alter table public.early_access_requests enable row level security;
drop policy if exists ear_read on public.early_access_requests;
create policy ear_read on public.early_access_requests for select
  using (user_id = auth.uid() or is_app_admin());
-- RPCs: request_early_access(note) · admin_list_ea_requests() · admin_decide_ea_request(user, approve)
-- (full bodies in the applied migration; approve also inserts the early_access app_role).
