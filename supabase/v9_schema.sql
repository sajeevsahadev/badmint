-- =====================================================================
-- Badmint v9 — Playing Schedule, Match Poll, Attendees, Push Subscriptions
-- Run once in Supabase SQL Editor (safe re-run; uses CREATE OR REPLACE)
-- =====================================================================

-- ── Schedule: planned match days per club ──
CREATE TABLE IF NOT EXISTS club_schedule (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id         uuid        NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  scheduled_date  date        NOT NULL,
  facility_id     uuid        REFERENCES facilities(id) ON DELETE SET NULL,
  facility_name   text,                      -- free-text override (no facility record)
  created_by      uuid        NOT NULL REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  status          text        NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','cancelled')),
  UNIQUE(club_id, scheduled_date)
);

ALTER TABLE club_schedule ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "cs_member_select" ON club_schedule FOR SELECT
    USING (EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = club_schedule.club_id AND cm.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "cs_member_insert" ON club_schedule FOR INSERT
    WITH CHECK (
      auth.uid() = created_by AND
      EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = club_schedule.club_id AND cm.user_id = auth.uid())
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "cs_member_update" ON club_schedule FOR UPDATE
    USING (EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = club_schedule.club_id AND cm.user_id = auth.uid()));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ── Poll votes: attending / not_attending ──
CREATE TABLE IF NOT EXISTS schedule_votes (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id uuid        NOT NULL REFERENCES club_schedule(id) ON DELETE CASCADE,
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vote        text        NOT NULL CHECK (vote IN ('attending','not_attending')),
  voted_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE(schedule_id, user_id)
);

ALTER TABLE schedule_votes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "sv_member_select" ON schedule_votes FOR SELECT
    USING (EXISTS (
      SELECT 1 FROM club_schedule cs JOIN club_members cm ON cm.club_id = cs.club_id
      WHERE cs.id = schedule_votes.schedule_id AND cm.user_id = auth.uid()
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "sv_own_insert" ON schedule_votes FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "sv_own_update" ON schedule_votes FOR UPDATE USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "sv_own_delete" ON schedule_votes FOR DELETE USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ── Actual attendees on match day (separate from poll) ──
CREATE TABLE IF NOT EXISTS schedule_attendees (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id uuid        NOT NULL REFERENCES club_schedule(id) ON DELETE CASCADE,
  player_id   uuid        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  added_by    uuid        NOT NULL REFERENCES auth.users(id),
  added_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE(schedule_id, player_id)
);

ALTER TABLE schedule_attendees ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "sa_member_all" ON schedule_attendees FOR ALL
    USING (EXISTS (
      SELECT 1 FROM club_schedule cs JOIN club_members cm ON cm.club_id = cs.club_id
      WHERE cs.id = schedule_attendees.schedule_id AND cm.user_id = auth.uid()
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ── Push subscriptions (Web Push API endpoint + keys) ──
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  club_id    uuid        NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  endpoint   text        NOT NULL,
  p256dh     text        NOT NULL,
  auth_key   text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, endpoint)
);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "ps_own_all" ON push_subscriptions FOR ALL USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- =====================================================================
-- RPCs
-- =====================================================================

-- Create or update a schedule entry (upserts on conflict)
CREATE OR REPLACE FUNCTION create_schedule(
  p_club_id       uuid,
  p_date          date,
  p_facility_id   uuid DEFAULT NULL,
  p_facility_name text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;

  INSERT INTO club_schedule(club_id, scheduled_date, facility_id, facility_name, created_by)
  VALUES (p_club_id, p_date, p_facility_id, p_facility_name, auth.uid())
  ON CONFLICT (club_id, scheduled_date) DO UPDATE SET
    facility_id   = EXCLUDED.facility_id,
    facility_name = EXCLUDED.facility_name
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION create_schedule(uuid, date, uuid, text) TO authenticated;


-- Monthly schedule for a club (includes vote counts + caller's vote)
CREATE OR REPLACE FUNCTION get_club_schedule(
  p_club_id uuid,
  p_year    int,
  p_month   int
) RETURNS TABLE (
  id                  uuid,
  scheduled_date      date,
  facility_id         uuid,
  facility_name       text,
  fac_name            text,
  status              text,
  attending_count     int,
  not_attending_count int,
  my_vote             text
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member';
  END IF;

  RETURN QUERY
  SELECT
    cs.id,
    cs.scheduled_date,
    cs.facility_id,
    cs.facility_name,
    f.name                                                               AS fac_name,
    cs.status,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'attending')::int              AS attending_count,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'not_attending')::int          AS not_attending_count,
    MAX(sv.vote) FILTER (WHERE sv.user_id = auth.uid())                 AS my_vote
  FROM club_schedule cs
  LEFT JOIN facilities f ON f.id = cs.facility_id
  LEFT JOIN schedule_votes sv ON sv.schedule_id = cs.id
  WHERE cs.club_id = p_club_id
    AND EXTRACT(YEAR  FROM cs.scheduled_date) = p_year
    AND EXTRACT(MONTH FROM cs.scheduled_date) = p_month
  GROUP BY cs.id, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name, cs.status;
END;
$$;
GRANT EXECUTE ON FUNCTION get_club_schedule(uuid, int, int) TO authenticated;


-- Schedule detail by ID (public — used for shareable poll URL)
CREATE OR REPLACE FUNCTION get_schedule_detail(p_schedule_id uuid)
RETURNS TABLE (
  id                  uuid,
  club_id             uuid,
  club_name           text,
  scheduled_date      date,
  facility_id         uuid,
  facility_name       text,
  fac_name            text,
  status              text,
  attending_count     int,
  not_attending_count int,
  my_vote             text
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    cs.id,
    cs.club_id,
    c.name                                                               AS club_name,
    cs.scheduled_date,
    cs.facility_id,
    cs.facility_name,
    f.name                                                               AS fac_name,
    cs.status,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'attending')::int              AS attending_count,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'not_attending')::int          AS not_attending_count,
    MAX(sv.vote) FILTER (WHERE sv.user_id = auth.uid())                 AS my_vote
  FROM club_schedule cs
  JOIN  clubs c ON c.id = cs.club_id
  LEFT JOIN facilities f ON f.id = cs.facility_id
  LEFT JOIN schedule_votes sv ON sv.schedule_id = cs.id
  WHERE cs.id = p_schedule_id
  GROUP BY cs.id, cs.club_id, c.name, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name, cs.status;
END;
$$;
GRANT EXECUTE ON FUNCTION get_schedule_detail(uuid) TO anon, authenticated;


-- Upsert a vote (attending / not_attending)
CREATE OR REPLACE FUNCTION vote_schedule(
  p_schedule_id uuid,
  p_vote        text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club_id uuid;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = v_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;

  INSERT INTO schedule_votes(schedule_id, user_id, vote, voted_at)
  VALUES (p_schedule_id, auth.uid(), p_vote, now())
  ON CONFLICT (schedule_id, user_id) DO UPDATE SET vote = EXCLUDED.vote, voted_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION vote_schedule(uuid, text) TO authenticated;


-- Get all votes with display names (members only)
CREATE OR REPLACE FUNCTION get_schedule_votes(p_schedule_id uuid)
RETURNS TABLE (
  user_id      uuid,
  vote         text,
  voted_at     timestamptz,
  display_name text
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club_id uuid;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = v_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member';
  END IF;

  RETURN QUERY
  SELECT
    sv.user_id,
    sv.vote,
    sv.voted_at,
    COALESCE(up.nickname, pl.display_name, split_part(u.email, '@', 1)) AS display_name
  FROM schedule_votes sv
  JOIN  auth.users u ON u.id = sv.user_id
  LEFT JOIN user_profiles up ON up.user_id = sv.user_id
  LEFT JOIN players pl ON pl.user_id = sv.user_id AND pl.club_id = v_club_id
  WHERE sv.schedule_id = p_schedule_id
  ORDER BY sv.voted_at ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_schedule_votes(uuid) TO authenticated;


-- Replace the full attendee list for a schedule
CREATE OR REPLACE FUNCTION set_schedule_attendees(
  p_schedule_id uuid,
  p_player_ids  uuid[]
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club_id uuid;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = v_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member';
  END IF;

  DELETE FROM schedule_attendees WHERE schedule_id = p_schedule_id;

  IF p_player_ids IS NOT NULL AND array_length(p_player_ids, 1) > 0 THEN
    INSERT INTO schedule_attendees(schedule_id, player_id, added_by)
    SELECT p_schedule_id, unnest(p_player_ids), auth.uid();
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION set_schedule_attendees(uuid, uuid[]) TO authenticated;


-- Get attendees for a schedule (returns player rows for AddMatch filter)
CREATE OR REPLACE FUNCTION get_schedule_attendees(p_schedule_id uuid)
RETURNS TABLE (player_id uuid, display_name text, elo numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_club_id uuid;
BEGIN
  SELECT club_id INTO v_club_id FROM club_schedule WHERE id = p_schedule_id;
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = v_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member';
  END IF;

  RETURN QUERY
  SELECT p.id AS player_id, p.display_name, p.elo
  FROM schedule_attendees sa
  JOIN players p ON p.id = sa.player_id
  WHERE sa.schedule_id = p_schedule_id
  ORDER BY p.display_name;
END;
$$;
GRANT EXECUTE ON FUNCTION get_schedule_attendees(uuid) TO authenticated;


-- Save / update a browser push subscription for a club
CREATE OR REPLACE FUNCTION save_push_subscription(
  p_club_id  uuid,
  p_endpoint text,
  p_p256dh   text,
  p_auth     text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO push_subscriptions(user_id, club_id, endpoint, p256dh, auth_key)
  VALUES (auth.uid(), p_club_id, p_endpoint, p_p256dh, p_auth)
  ON CONFLICT (user_id, endpoint) DO UPDATE SET
    club_id  = EXCLUDED.club_id,
    p256dh   = EXCLUDED.p256dh,
    auth_key = EXCLUDED.auth_key;
END;
$$;
GRANT EXECUTE ON FUNCTION save_push_subscription(uuid, text, text, text) TO authenticated;
