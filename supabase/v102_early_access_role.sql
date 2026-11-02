-- Phase 1: Early Access role for the premium AI Match Analysis feature.
-- app_admin can grant 'early_access'; holders (and admins) unlock the AI features.
-- Applied to bdmiirppiyopmdfrztoz via MCP.

create or replace function public.grant_role(
  p_user_id uuid, p_role text, p_tournament_quota integer default null,
  p_facility_id uuid default null, p_notes text default null)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  if not is_app_admin() then
    raise exception 'Only app admins can grant roles';
  end if;
  if p_role not in ('app_admin','tournament_director','facility_manager','early_access') then
    raise exception 'Invalid role: %', p_role;
  end if;
  insert into app_roles (user_id, role, tournament_quota, facility_id, granted_by, notes)
  values (p_user_id, p_role, p_tournament_quota, p_facility_id, auth.uid(), p_notes)
  on conflict (user_id, role) do update
    set tournament_quota = coalesce(excluded.tournament_quota, app_roles.tournament_quota),
        facility_id      = coalesce(excluded.facility_id,      app_roles.facility_id),
        notes            = coalesce(excluded.notes,            app_roles.notes),
        granted_by       = excluded.granted_by,
        granted_at       = now();
end;
$function$;

create or replace function public.has_early_access()
returns boolean language sql security definer set search_path to 'public' stable as $$
  select exists (
    select 1 from app_roles
    where user_id = auth.uid() and role in ('early_access','app_admin')
  );
$$;
grant execute on function public.has_early_access() to authenticated;
