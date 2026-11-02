-- v102 added 'early_access' to grant_role's whitelist but not to the app_roles CHECK constraint,
-- which would reject every early_access insert. Widen the constraint. Applied via MCP.
alter table public.app_roles drop constraint if exists app_roles_role_check;
alter table public.app_roles add constraint app_roles_role_check
  check (role = any (array['app_admin','tournament_director','facility_manager','early_access']));

-- One-off: grant early_access to all current app admins.
insert into public.app_roles (user_id, role, granted_at, notes)
select a.user_id, 'early_access', now(), 'Bulk-granted to all app admins'
from public.app_roles a
where a.role = 'app_admin'
on conflict (user_id, role) do nothing;
