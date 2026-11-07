-- v151: Admin Panel Roles tab — everyone who holds an app role, uncapped (get_all_users is LIMIT 100,
-- which silently hid holders once the platform passed 100 users). App admin only.

create or replace function public.admin_get_role_holders()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_app_admin() then raise exception 'Not allowed'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'user_id', u.id, 'email', u.email,
        'nickname', up.nickname,
        'full_name', coalesce(up.full_name, u.raw_user_meta_data->>'full_name'),
        'tournaments_created', (select count(*) from tournaments t where t.created_by = u.id),
        'roles', (select jsonb_agg(jsonb_build_object('role', ar.role, 'tournament_quota', ar.tournament_quota,
                    'facility_id', ar.facility_id, 'granted_at', ar.granted_at, 'notes', ar.notes))
                    from app_roles ar where ar.user_id = u.id))
      order by coalesce(up.nickname, up.full_name, u.email))
    from auth.users u
    left join user_profiles up on up.user_id = u.id
    where exists (select 1 from app_roles ar where ar.user_id = u.id)), '[]'::jsonb);
end $$;

revoke all on function public.admin_get_role_holders() from public, anon;
grant execute on function public.admin_get_role_holders() to authenticated;
