-- v40: Rotation & Fairness Engine — track consecutive matches per player per session
-- Run this in Supabase SQL Editor after v39_schema.sql

CREATE TABLE IF NOT EXISTS session_rotations (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id             uuid NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  session_date        date NOT NULL DEFAULT current_date,
  player_id           uuid NOT NULL REFERENCES players(id),
  matches_played      int  NOT NULL DEFAULT 0,
  last_played_at      timestamptz,
  consecutive_matches int  NOT NULL DEFAULT 0,
  UNIQUE(club_id, session_date, player_id)
);

ALTER TABLE session_rotations ENABLE ROW LEVEL SECURITY;

CREATE POLICY sr_read ON session_rotations FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM club_members cm
    WHERE cm.club_id = session_rotations.club_id AND cm.user_id = auth.uid()
  )
);

CREATE POLICY sr_write ON session_rotations FOR ALL USING (
  EXISTS (
    SELECT 1 FROM club_members cm
    WHERE cm.club_id = session_rotations.club_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('owner','manager')
  )
);

-- ── update_rotation_stats ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_rotation_stats(
  p_club_id      uuid,
  p_session_date date,
  p_played_ids   uuid[],
  p_bench_ids    uuid[]
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_role text;
  v_pid  uuid;
BEGIN
  SELECT role INTO v_role FROM club_members
  WHERE club_id = p_club_id AND user_id = auth.uid();
  IF v_role NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'Only managers can update rotation stats';
  END IF;

  FOREACH v_pid IN ARRAY p_played_ids LOOP
    INSERT INTO session_rotations (club_id, session_date, player_id, matches_played, consecutive_matches, last_played_at)
    VALUES (p_club_id, p_session_date, v_pid, 1, 1, now())
    ON CONFLICT (club_id, session_date, player_id) DO UPDATE
      SET matches_played      = session_rotations.matches_played + 1,
          consecutive_matches = session_rotations.consecutive_matches + 1,
          last_played_at      = now();
  END LOOP;

  FOREACH v_pid IN ARRAY COALESCE(p_bench_ids, '{}') LOOP
    INSERT INTO session_rotations (club_id, session_date, player_id, matches_played, consecutive_matches, last_played_at)
    VALUES (p_club_id, p_session_date, v_pid, 0, 0, NULL)
    ON CONFLICT (club_id, session_date, player_id) DO UPDATE
      SET consecutive_matches = 0;
  END LOOP;
END;
$$;

-- ── get_rotation_summary ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_rotation_summary(
  p_club_id      uuid,
  p_session_date date DEFAULT current_date
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'player_id',           sr.player_id,
      'name',                COALESCE(up.nickname, p.display_name),
      'matches_played',      sr.matches_played,
      'consecutive_matches', sr.consecutive_matches,
      'last_played_at',      sr.last_played_at
    ) ORDER BY sr.consecutive_matches DESC, sr.matches_played DESC
  )
  INTO v_result
  FROM session_rotations sr
  JOIN players p ON p.id = sr.player_id
  LEFT JOIN user_profiles up ON up.user_id = p.user_id
  WHERE sr.club_id = p_club_id AND sr.session_date = p_session_date;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION update_rotation_stats(uuid, date, uuid[], uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_rotation_summary(uuid, date) TO authenticated;
