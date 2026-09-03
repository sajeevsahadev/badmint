-- v106_player_tournament_honours
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Public list of a player's tournament podium finishes, newest first.
CREATE OR REPLACE FUNCTION public.get_player_tournament_honours(p_user_id uuid)
RETURNS TABLE(tournament_id uuid, tournament_name text, share_code text,
              club_name text, placement int, end_date date)
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT t.id, t.name, t.share_code, c.name, ptr.placement, t.end_date
  FROM player_tournament_results ptr
  JOIN tournaments t ON t.id = ptr.tournament_id
  JOIN clubs c ON c.id = t.club_id
  WHERE ptr.user_id = p_user_id
  ORDER BY ptr.placement ASC, COALESCE(t.end_date, t.start_date) DESC NULLS LAST;
$$;
GRANT EXECUTE ON FUNCTION public.get_player_tournament_honours(uuid) TO anon, authenticated;;
