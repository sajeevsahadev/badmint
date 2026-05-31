-- =====================================================================
-- Badmint v7 — Leave Club
-- Run once in Supabase SQL Editor
-- =====================================================================

-- Players can voluntarily leave a club IF they have no match history.
-- Owners cannot leave (they must transfer ownership first).
create or replace function leave_club(p_club_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_player_id uuid;
begin
  -- Owners cannot leave
  if exists (
    select 1 from club_members
    where club_id = p_club_id and user_id = auth.uid() and role = 'owner'
  ) then
    raise exception 'Club owners cannot leave. Transfer ownership first via Manage → Members.';
  end if;

  -- Must actually be a member
  if not exists (
    select 1 from club_members
    where club_id = p_club_id and user_id = auth.uid()
  ) then
    raise exception 'You are not a member of this club.';
  end if;

  -- Find this user''s player row in the club
  select id into v_player_id
  from players
  where club_id = p_club_id and user_id = auth.uid();

  -- Block if they have match history (Elo must stay in history)
  if v_player_id is not null and exists(
    select 1 from match_participants where player_id = v_player_id
  ) then
    raise exception 'You have match history in this club. Ask the manager to mark you as Inactive instead.';
  end if;

  -- Remove player row (no match history, safe to delete)
  delete from players where id = v_player_id;

  -- Remove club membership
  delete from club_members where club_id = p_club_id and user_id = auth.uid();
end;
$$;
