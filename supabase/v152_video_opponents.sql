-- v152: named, reusable OPPONENTS for AI video tagging (tournament opponents who aren't club members).
-- Stored as players rows with is_opponent = true and is_active = false, so they:
--   * never appear in the leaderboard / top scorers / Add Match (all filter is_active),
--   * are hidden from the roster (get_club_players below) and Compare,
--   * still get AI reports attached to their player id, so later videos of the same opponent build up
--     a picture of their game plan.
alter table public.players add column if not exists is_opponent boolean not null default false;

create or replace function public.create_opponent(p_club_id uuid, p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_name text := nullif(trim(p_name), '');
begin
  if v_name is null then raise exception 'Name is required'; end if;
  if length(v_name) > 60 then raise exception 'Name is too long'; end if;
  if not public.is_member(p_club_id) then raise exception 'Not allowed'; end if;
  select id into v_id from players
   where club_id = p_club_id and is_opponent and lower(display_name) = lower(v_name) limit 1;
  if v_id is not null then return v_id; end if;           -- reuse an existing opponent with that name
  insert into players (club_id, display_name, is_active, is_opponent)
  values (p_club_id, v_name, false, true) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.create_opponent(uuid, text) to authenticated;

create or replace function public.get_club_opponents(p_club_id uuid)
returns table(id uuid, display_name text) language sql stable security definer set search_path = public as $$
  select p.id, p.display_name from players p
   where p.club_id = p_club_id and p.is_opponent and public.is_member(p_club_id)
   order by p.display_name
$$;
grant execute on function public.get_club_opponents(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.get_club_players(p_club_id uuid)
 RETURNS TABLE(id uuid, display_name text, elo numeric, is_active boolean, user_id uuid, last_seen_at timestamp with time zone, online_status text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT p.id, COALESCE(up.nickname, p.display_name) AS display_name,
    p.elo, p.is_active, p.user_id, up.last_seen_at,
    CASE
      WHEN up.last_seen_at >= now() - interval '10 minutes' THEN 'online'
      WHEN up.last_seen_at >= now() - interval '1 month'    THEN 'recent'
      ELSE 'offline'
    END AS online_status
  FROM players p
  LEFT JOIN user_profiles up ON up.user_id = p.user_id
  WHERE p.club_id = p_club_id AND NOT p.is_opponent
  ORDER BY p.is_active DESC, p.elo DESC;
$function$;
