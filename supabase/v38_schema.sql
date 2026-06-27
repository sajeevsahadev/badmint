-- =====================================================================
-- Badmint v38 — Smart Lineup Suggestion
-- Reads from schedule_attendees (who marked as attending),
-- NOT from attendance (only populated after matches are recorded).
-- Available to ALL club members (not just managers).
-- =====================================================================

CREATE OR REPLACE FUNCTION suggest_lineup(
  p_schedule_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_club_id      uuid;
  v_date         date;
  v_member       boolean;
  v_attendee_ids uuid[];
  v_recent_ids   uuid[];
  v_players      jsonb;
  v_count        int;
  v_p0 jsonb; v_p1 jsonb; v_p2 jsonb; v_p3 jsonb;
  v_bench        jsonb;
BEGIN
  -- Resolve club_id and date from schedule
  SELECT club_id, scheduled_date INTO v_club_id, v_date
  FROM club_schedule WHERE id = p_schedule_id;

  IF v_club_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Schedule not found');
  END IF;

  -- Any club member may call this
  SELECT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_club_id AND user_id = auth.uid()
  ) INTO v_member;
  IF NOT v_member THEN
    RAISE EXCEPTION 'Club membership required';
  END IF;

  -- 1. Get players from schedule_attendees (actual attendance list saved by manager)
  SELECT array_agg(sa.player_id)
  INTO v_attendee_ids
  FROM schedule_attendees sa
  WHERE sa.schedule_id = p_schedule_id;

  IF v_attendee_ids IS NULL OR array_length(v_attendee_ids, 1) < 4 THEN
    RETURN jsonb_build_object(
      'error', 'Need at least 4 players in the Actual Attendees list'
    );
  END IF;

  -- 2. Who played in the MOST RECENT match today? (deprioritize for rotation)
  SELECT array_agg(DISTINCT mp.player_id)
  INTO v_recent_ids
  FROM matches m
  JOIN match_sides ms ON ms.match_id = m.id
  JOIN match_participants mp ON mp.match_side_id = ms.id
  WHERE m.club_id = v_club_id
    AND m.played_on = v_date
    AND m.created_at = (
      SELECT MAX(m2.created_at)
      FROM matches m2
      WHERE m2.club_id = v_club_id AND m2.played_on = v_date
    );

  -- 3. Build sorted candidates:
  --    Primary: NOT in last match first (rotation fairness)
  --    Secondary: Elo DESC (for snake-draft balancing)
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',     p.id,
      'name',   COALESCE(up.nickname, p.display_name),
      'elo',    p.elo,
      'rested', NOT (v_recent_ids IS NOT NULL AND p.id = ANY(v_recent_ids))
    )
    ORDER BY
      CASE WHEN v_recent_ids IS NOT NULL AND p.id = ANY(v_recent_ids) THEN 1 ELSE 0 END ASC,
      p.elo DESC
  )
  INTO v_players
  FROM players p
  LEFT JOIN user_profiles up ON up.user_id = p.user_id
  WHERE p.id = ANY(v_attendee_ids)
    AND p.is_active = true;

  v_count := jsonb_array_length(v_players);
  IF v_count < 4 THEN
    RETURN jsonb_build_object('error', 'Not enough active players in attendance');
  END IF;

  -- 4. Snake-draft top 4: rank 1 & 4 vs rank 2 & 3
  --    e.g. Elos [1200, 1100, 1000, 900] → A:[1200,900]=2100 vs B:[1100,1000]=2100
  v_p0 := v_players->0;
  v_p1 := v_players->1;
  v_p2 := v_players->2;
  v_p3 := v_players->3;

  -- Bench = attendees beyond top 4
  IF v_count > 4 THEN
    SELECT jsonb_agg(v_players->i ORDER BY i)
    INTO v_bench
    FROM generate_series(4, v_count - 1) AS i;
  ELSE
    v_bench := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'side_a',           jsonb_build_array(v_p0, v_p3),
    'side_b',           jsonb_build_array(v_p1, v_p2),
    'elo_a',            (v_p0->>'elo')::int + (v_p3->>'elo')::int,
    'elo_b',            (v_p1->>'elo')::int + (v_p2->>'elo')::int,
    'bench',            v_bench,
    'rotated',          v_recent_ids IS NOT NULL,
    'total_attending',  v_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION suggest_lineup(uuid) TO authenticated;
