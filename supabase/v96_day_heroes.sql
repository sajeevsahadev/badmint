-- v96_day_heroes
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Standouts from the club's most recent match day (per-player games/wins/Elo Δ
-- for that date). Powers the "Today's Heroes" card on the Scoreboard so recent
-- performance is celebrated, not just all-time Elo. SECURITY DEFINER to bypass
-- RLS the same way the other public scoreboard RPCs do.
CREATE OR REPLACE FUNCTION public.get_day_heroes(p_club_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_date    date;
  v_players jsonb;
BEGIN
  SELECT max(played_on) INTO v_date FROM matches WHERE club_id = p_club_id;
  IF v_date IS NULL THEN
    RETURN jsonb_build_object('date', NULL, 'players', '[]'::jsonb);
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb) INTO v_players
  FROM (
    SELECT
      p.id                                                        AS player_id,
      p.user_id                                                   AS user_id,
      COALESCE(resolve_public_nickname(p.user_id), p.display_name) AS name,
      count(*)::int                                               AS games,
      count(*) FILTER (WHERE ms.is_winner)::int                   AS wins,
      round(sum(mp.elo_after - mp.elo_before))::int               AS delta
    FROM match_participants mp
    JOIN match_sides ms ON ms.id = mp.match_side_id
    JOIN matches     m  ON m.id  = ms.match_id
    JOIN players     p  ON p.id  = mp.player_id
    WHERE m.club_id = p_club_id AND m.played_on = v_date
    GROUP BY p.id, p.user_id, p.display_name
    ORDER BY delta DESC, wins DESC, games DESC
  ) t;

  RETURN jsonb_build_object('date', v_date, 'players', v_players);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_day_heroes(uuid) TO authenticated, anon;;
