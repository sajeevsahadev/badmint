-- =====================================================================
-- Badmint v8 — 5-club limit + revoke join request
-- Run once in Supabase SQL Editor (safe re-run; uses CREATE OR REPLACE)
-- =====================================================================

-- ── RLS: allow users to delete their own pending requests ──
-- (needed by revoke_join_request; safe to run even if policy already exists)
do $$ begin
  create policy jr_delete_own on join_requests for delete
    using (user_id = auth.uid() and status = 'pending');
exception when duplicate_object then null; end $$;


-- ── Updated request_join: enforce max 5 clubs per user ──
-- Counts current memberships + pending requests.
-- Replaces the version in join_schema.sql.
create or replace function request_join(p_club_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_email  text;
  v_name   text;
  v_total  integer;
begin
  -- Enforce 5-club limit (memberships + pending requests)
  select
    (select count(*) from club_members  where user_id = auth.uid()) +
    (select count(*) from join_requests where user_id = auth.uid() and status = 'pending')
  into v_total;

  if v_total >= 5 then
    raise exception 'You have reached the maximum of 5 clubs. Leave a club or revoke a pending request before joining another.';
  end if;

  -- Resolve caller name / email
  select
    u.email,
    coalesce(
      u.raw_user_meta_data->>'full_name',
      u.raw_user_meta_data->>'name',
      split_part(u.email, '@', 1)
    )
  into v_email, v_name
  from auth.users u where u.id = auth.uid();

  -- Insert new request; if a previous request was rejected, reset it to pending.
  -- If already pending or approved: do nothing (no silent overwrite of approved).
  insert into join_requests(club_id, user_id, user_email, user_name)
    values (p_club_id, auth.uid(), v_email, v_name)
    on conflict (club_id, user_id) do update
      set status = 'pending', created_at = now()
      where join_requests.status = 'rejected';
end;
$$;

grant execute on function request_join(uuid) to authenticated;


-- ── revoke_join_request: cancel a pending request ──
-- Player can call this themselves to withdraw a pending request.
create or replace function revoke_join_request(p_club_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from join_requests
  where club_id   = p_club_id
    and user_id   = auth.uid()
    and status    = 'pending';

  if not found then
    raise exception 'No pending request found for this club.';
  end if;
end;
$$;

grant execute on function revoke_join_request(uuid) to authenticated;
