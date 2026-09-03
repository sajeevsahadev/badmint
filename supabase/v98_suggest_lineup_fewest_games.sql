-- v98_suggest_lineup_fewest_games
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Next-match suggestion, unified with the Game Plan engine (utils/game-plan.js):
-- pick the 4 with the FEWEST games played today (strict fair rotation — so a
-- player never plays 3 in a row while others sit), break ties toward whoever did
-- NOT just play, then higher Elo, then a stable id. Fully deterministic when
-- p_shuffle=false, so the same attendees + same recorded games always yield the
-- same suggestion (matching the Schedule page's "Generate Plan"). p_shuffle keeps
-- the explicit random reshuffle.
CREATE OR REPLACE FUNCTION public.suggest_lineup_by_date(p_club_id uuid, p_date date DEFAULT CURRENT_DATE, p_shuffle boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_member       boolean;
  v_schedule_id  uuid;
  v_attendee_ids uuid[];
  v_recent_ids   uuid[];
  v_play  jsonb;
  v_bench jsonb;
  v_count int;
  v_p0 jsonb; v_p1 jsonb; v_p2 jsonb; v_p3 jsonb;
BEGIN
  SELECT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid())
  INTO v_member;
  IF NOT v_member THEN RAISE EXCEPTION 'Club membership required'; END IF;

  SELECT id INTO v_schedule_id
  FROM club_schedule WHERE club_id = p_club_id AND scheduled_date = p_date LIMIT 1;

  IF v_schedule_id IS NOT NULL THEN
    SELECT array_agg(sa.player_id) INTO v_attendee_ids
    FROM schedule_attendees sa WHERE sa.schedule_id = v_schedule_id;
  END IF;

  IF v_attendee_ids IS NULL OR array_length(v_attendee_ids, 1) < 4 THEN
    SELECT array_agg(p.id) INTO v_attendee_ids
    FROM players p WHERE p.club_id = p_club_id AND p.is_active = true;
  END IF;

  IF v_attendee_ids IS NULL OR array_length(v_attendee_ids, 1) < 4 THEN
    RETURN jsonb_build_object('error', 'Need at least 4 active players in the club');
  END IF;

  -- Who played the most recent match today (tie-break: they rest before an equally-rested peer)
  SELECT array_agg(DISTINCT mp.player_id) INTO v_recent_ids
  FROM matches m
  JOIN match_sides ms ON ms.match_id = m.id
  JOIN match_participants mp ON mp.match_side_id = ms.id
  WHERE m.club_id = p_club_id AND m.played_on = p_date
    AND m.created_at = (SELECT MAX(m2.created_at) FROM matches m2
                        WHERE m2.club_id = p_club_id AND m2.played_on = p_date);

  WITH games_today AS (
    SELECT mp.player_id, count(*) AS g
    FROM matches m
    JOIN match_sides ms ON ms.match_id = m.id
    JOIN match_participants mp ON mp.match_side_id = ms.id
    WHERE m.club_id = p_club_id AND m.played_on = p_date
    GROUP BY mp.player_id
  ),
  pool AS (
    SELECT p.id,
           COALESCE(up.nickname, p.display_name) AS name,
           p.elo::numeric::int AS elo,
           COALESCE(gt.g, 0) AS games,
           (v_recent_ids IS NOT NULL AND p.id = ANY(v_recent_ids)) AS in_recent
    FROM players p
    LEFT JOIN user_profiles up ON up.user_id = p.user_id
    LEFT JOIN games_today gt ON gt.player_id = p.id
    WHERE p.id = ANY(v_attendee_ids) AND p.is_active = true
  ),
  ranked AS MATERIALIZED (
    SELECT *, row_number() OVER (
      ORDER BY
        CASE WHEN p_shuffle THEN 0 ELSE games END,                                  -- fewest games first
        CASE WHEN p_shuffle THEN 0 ELSE (CASE WHEN in_recent THEN 1 ELSE 0 END) END, -- didn't just play first
        CASE WHEN p_shuffle THEN random() ELSE (1000000 - elo) END,                  -- higher Elo
        id                                                                           -- stable final tie-break
    ) AS sel
    FROM pool
  )
  SELECT
    (SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'elo',elo,'rested', NOT in_recent) ORDER BY elo DESC)
       FROM ranked WHERE sel <= 4),
    (SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'elo',elo,'rested', NOT in_recent) ORDER BY elo DESC)
       FROM ranked WHERE sel > 4),
    (SELECT count(*) FROM pool)
  INTO v_play, v_bench, v_count;

  IF v_count < 4 THEN RETURN jsonb_build_object('error', 'Not enough active players'); END IF;
  v_bench := COALESCE(v_bench, '[]'::jsonb);

  v_p0 := v_play->0; v_p1 := v_play->1; v_p2 := v_play->2; v_p3 := v_play->3;

  RETURN jsonb_build_object(
    'side_a', jsonb_build_array(v_p0, v_p3),
    'side_b', jsonb_build_array(v_p1, v_p2),
    'elo_a',  (v_p0->>'elo')::int + (v_p3->>'elo')::int,
    'elo_b',  (v_p1->>'elo')::int + (v_p2->>'elo')::int,
    'bench',  v_bench,
    'rotated', v_recent_ids IS NOT NULL AND NOT p_shuffle,
    'total_attending', v_count,
    'used_schedule', v_schedule_id IS NOT NULL
  );
END;
$function$;;
