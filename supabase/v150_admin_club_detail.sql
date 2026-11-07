-- v150: Admin Panel — club detail sheet. One call returns a club's profile, stats and every person
-- in it (account members with role + email, and guest/roster players without an account). App admin only.

create or replace function public.admin_get_club_detail(p_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_app_admin() then raise exception 'Not allowed'; end if;
  return (
    select jsonb_build_object(
      'club', jsonb_build_object(
        'id', c.id, 'name', c.name, 'description', c.description, 'logo_url', c.logo_url,
        'region', c.emirates, 'country_code', c.country_code, 'facility_name', c.facility_name,
        'facility_address', c.facility_address, 'join_policy', c.join_policy, 'is_public', c.is_public,
        'currency', c.currency, 'created_at', c.created_at, 'deleted_at', c.deleted_at,
        'created_by_email', (select email from auth.users where id = c.created_by)),
      'stats', jsonb_build_object(
        'members', (select count(*) from club_members m where m.club_id = c.id),
        'players', (select count(*) from players p where p.club_id = c.id),
        'active_players', (select count(*) from players p where p.club_id = c.id and p.is_active),
        'matches', (select count(*) from matches x where x.club_id = c.id),
        'matches_30d', (select count(*) from matches x where x.club_id = c.id and x.played_on >= current_date - 30),
        'last_played', (select max(played_on) from matches x where x.club_id = c.id),
        'pending_requests', (select count(*) from join_requests j where j.club_id = c.id and j.status = 'pending')),
      'members', coalesce((
        select jsonb_agg(jsonb_build_object(
            'user_id', m.user_id, 'role', m.role, 'joined_at', m.joined_at,
            'email', au.email,
            'name', coalesce(up.nickname, up.full_name, p.display_name, au.raw_user_meta_data->>'full_name', au.email),
            'player_id', p.id, 'elo', p.elo, 'is_active', p.is_active,
            'games', (select count(*) from match_participants mp where mp.player_id = p.id),
            'last_seen', up.last_seen_at,
            'app_roles', (select coalesce(jsonb_agg(r.role), '[]'::jsonb) from app_roles r where r.user_id = m.user_id))
          order by case m.role when 'owner' then 0 when 'manager' then 1 else 2 end, coalesce(up.nickname, p.display_name))
        from club_members m
        left join auth.users au on au.id = m.user_id
        left join user_profiles up on up.user_id = m.user_id
        left join players p on p.club_id = m.club_id and p.user_id = m.user_id
        where m.club_id = c.id), '[]'::jsonb),
      'guests', coalesce((
        select jsonb_agg(jsonb_build_object(
            'player_id', p.id, 'name', p.display_name, 'elo', p.elo, 'is_active', p.is_active,
            'pending_email', p.pending_email,
            'games', (select count(*) from match_participants mp where mp.player_id = p.id))
          order by p.display_name)
        from players p where p.club_id = c.id and p.user_id is null), '[]'::jsonb))
    from clubs c where c.id = p_club_id);
end $$;

revoke all on function public.admin_get_club_detail(uuid) from public, anon;
grant execute on function public.admin_get_club_detail(uuid) to authenticated;
