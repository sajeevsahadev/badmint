-- =====================================================================
-- Badmint v14 — Tournament Module
-- Run in Supabase SQL Editor after v13_schema.sql
-- =====================================================================

-- ── Tables ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tournaments (
  id                    uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  club_id               uuid NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  name                  text NOT NULL,
  description           text,
  format                text NOT NULL DEFAULT 'single_elimination',
  -- single_elimination | round_robin
  status                text NOT NULL DEFAULT 'draft',
  -- draft | registration_open | registration_closed | live | completed | cancelled
  max_teams             int  NOT NULL DEFAULT 16,
  entry_fee             numeric(10,2),
  prize_info            text,
  venue                 text,
  venue_address         text,
  maps_url              text,
  emirate               text,
  registration_end      date,
  start_date            date,
  end_date              date,
  is_public             boolean NOT NULL DEFAULT true,
  winner_registration_id uuid,   -- set when tournament completes
  created_by            uuid NOT NULL REFERENCES auth.users(id),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tournament_registrations (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  tournament_id  uuid NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  team_name      text NOT NULL,
  player_a_name  text NOT NULL,
  player_b_name  text,
  registered_by  uuid NOT NULL REFERENCES auth.users(id),
  status         text NOT NULL DEFAULT 'pending',
  -- pending | confirmed | rejected | withdrawn
  seed           int,
  notes          text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tournament_id, team_name)
);

CREATE TABLE IF NOT EXISTS tournament_matches (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  tournament_id   uuid NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  round           int  NOT NULL DEFAULT 1,
  position        int  NOT NULL,
  team_a_id       uuid REFERENCES tournament_registrations(id),
  team_b_id       uuid REFERENCES tournament_registrations(id),
  score_a         int,
  score_b         int,
  winner_id       uuid REFERENCES tournament_registrations(id),
  status          text NOT NULL DEFAULT 'scheduled',
  -- scheduled | completed | bye
  next_match_id   uuid REFERENCES tournament_matches(id),
  next_match_slot text,   -- 'a' or 'b'
  scheduled_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- ── Indexes ───────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_tournaments_club    ON tournaments(club_id);
CREATE INDEX IF NOT EXISTS idx_tournaments_status  ON tournaments(status);
CREATE INDEX IF NOT EXISTS idx_tourreg_tournament  ON tournament_registrations(tournament_id);
CREATE INDEX IF NOT EXISTS idx_tourmatch_tour      ON tournament_matches(tournament_id);

-- ── RLS (public read, writes via SECURITY DEFINER RPCs only) ─────────
ALTER TABLE tournaments              ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_matches       ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tournaments_read"       ON tournaments              FOR SELECT USING (true);
CREATE POLICY "tournament_regs_read"   ON tournament_registrations FOR SELECT USING (true);
CREATE POLICY "tournament_matches_read" ON tournament_matches      FOR SELECT USING (true);

-- ── Standings view (round-robin) ──────────────────────────────────────
CREATE OR REPLACE VIEW v_tournament_standings AS
SELECT
  tr.tournament_id,
  tr.id            AS registration_id,
  tr.team_name,
  tr.seed,
  COUNT(CASE WHEN tm.winner_id = tr.id THEN 1 END)                                     AS wins,
  COUNT(CASE WHEN tm.status = 'completed'
               AND (tm.team_a_id = tr.id OR tm.team_b_id = tr.id)
               AND tm.winner_id <> tr.id THEN 1 END)                                   AS losses,
  COUNT(CASE WHEN tm.status = 'completed'
               AND (tm.team_a_id = tr.id OR tm.team_b_id = tr.id) THEN 1 END)         AS played,
  COALESCE(SUM(CASE WHEN tm.team_a_id = tr.id AND tm.status='completed' THEN tm.score_a
                    WHEN tm.team_b_id = tr.id AND tm.status='completed' THEN tm.score_b
                    ELSE 0 END), 0)                                                     AS sets_for,
  COALESCE(SUM(CASE WHEN tm.team_a_id = tr.id AND tm.status='completed' THEN tm.score_b
                    WHEN tm.team_b_id = tr.id AND tm.status='completed' THEN tm.score_a
                    ELSE 0 END), 0)                                                     AS sets_against
FROM tournament_registrations tr
LEFT JOIN tournament_matches tm
  ON (tm.team_a_id = tr.id OR tm.team_b_id = tr.id)
WHERE tr.status = 'confirmed'
GROUP BY tr.tournament_id, tr.id, tr.team_name, tr.seed;

-- ══════════════════════════════════════════════════════════════════════
-- RPCs
-- ══════════════════════════════════════════════════════════════════════

-- ── create_tournament ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION create_tournament(
  p_club_id         uuid,
  p_name            text,
  p_format          text DEFAULT 'single_elimination',
  p_max_teams       int  DEFAULT 16,
  p_description     text DEFAULT NULL,
  p_entry_fee       numeric DEFAULT NULL,
  p_prize_info      text DEFAULT NULL,
  p_venue           text DEFAULT NULL,
  p_venue_address   text DEFAULT NULL,
  p_emirate         text DEFAULT NULL,
  p_registration_end date DEFAULT NULL,
  p_start_date      date DEFAULT NULL,
  p_end_date        date DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid()
      AND role IN ('owner','manager')
  ) THEN RAISE EXCEPTION 'Only club managers or owners can create tournaments'; END IF;

  IF p_format NOT IN ('single_elimination','round_robin') THEN
    RAISE EXCEPTION 'Invalid format. Use single_elimination or round_robin';
  END IF;

  INSERT INTO tournaments (
    club_id, name, format, max_teams, description,
    entry_fee, prize_info, venue, venue_address, emirate,
    registration_end, start_date, end_date, created_by
  ) VALUES (
    p_club_id, p_name, p_format, p_max_teams, p_description,
    p_entry_fee, p_prize_info, p_venue, p_venue_address, p_emirate,
    p_registration_end, p_start_date, p_end_date, auth.uid()
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_tournament(uuid,text,text,int,text,numeric,text,text,text,text,date,date,date) TO authenticated;

-- ── update_tournament_status ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_tournament_status(
  p_tournament_id uuid,
  p_status        text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tour record;
BEGIN
  SELECT * INTO v_tour FROM tournaments WHERE id = p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;

  IF NOT (v_tour.created_by = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_tour.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  )) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF p_status NOT IN ('draft','registration_open','registration_closed','live','completed','cancelled') THEN
    RAISE EXCEPTION 'Invalid status';
  END IF;

  UPDATE tournaments SET status = p_status, updated_at = now() WHERE id = p_tournament_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_tournament_status(uuid,text) TO authenticated;

-- ── update_tournament_details ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_tournament_details(
  p_tournament_id   uuid,
  p_name            text DEFAULT NULL,
  p_description     text DEFAULT NULL,
  p_entry_fee       numeric DEFAULT NULL,
  p_prize_info      text DEFAULT NULL,
  p_venue           text DEFAULT NULL,
  p_venue_address   text DEFAULT NULL,
  p_emirate         text DEFAULT NULL,
  p_registration_end date DEFAULT NULL,
  p_start_date      date DEFAULT NULL,
  p_end_date        date DEFAULT NULL,
  p_max_teams       int  DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tour record;
BEGIN
  SELECT * INTO v_tour FROM tournaments WHERE id = p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF NOT (v_tour.created_by = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_tour.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  )) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  UPDATE tournaments SET
    name             = COALESCE(p_name,             name),
    description      = COALESCE(p_description,      description),
    entry_fee        = COALESCE(p_entry_fee,         entry_fee),
    prize_info       = COALESCE(p_prize_info,        prize_info),
    venue            = COALESCE(p_venue,             venue),
    venue_address    = COALESCE(p_venue_address,     venue_address),
    emirate          = COALESCE(p_emirate,           emirate),
    registration_end = COALESCE(p_registration_end, registration_end),
    start_date       = COALESCE(p_start_date,        start_date),
    end_date         = COALESCE(p_end_date,          end_date),
    max_teams        = COALESCE(p_max_teams,         max_teams),
    updated_at       = now()
  WHERE id = p_tournament_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_tournament_details(uuid,text,text,numeric,text,text,text,text,date,date,date,int) TO authenticated;

-- ── register_for_tournament ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION register_for_tournament(
  p_tournament_id uuid,
  p_team_name     text,
  p_player_a_name text,
  p_player_b_name text DEFAULT NULL,
  p_notes         text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tour record;
  v_count int;
  v_id    uuid;
BEGIN
  SELECT * INTO v_tour FROM tournaments WHERE id = p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF v_tour.status <> 'registration_open' THEN
    RAISE EXCEPTION 'Registration is not open for this tournament';
  END IF;

  -- Check capacity
  SELECT COUNT(*) INTO v_count
  FROM tournament_registrations
  WHERE tournament_id = p_tournament_id AND status IN ('pending','confirmed');
  IF v_count >= v_tour.max_teams THEN
    RAISE EXCEPTION 'Tournament is full (% teams)', v_tour.max_teams;
  END IF;

  INSERT INTO tournament_registrations (
    tournament_id, team_name, player_a_name, player_b_name,
    registered_by, notes
  ) VALUES (
    p_tournament_id, trim(p_team_name), trim(p_player_a_name),
    NULLIF(trim(p_player_b_name),''), p_notes, auth.uid()
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION register_for_tournament(uuid,text,text,text,text) TO authenticated;

-- ── approve_registration ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION approve_registration(p_reg_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_reg record;
BEGIN
  SELECT tr.*, t.club_id, t.created_by AS tour_creator
  INTO v_reg
  FROM tournament_registrations tr
  JOIN tournaments t ON t.id = tr.tournament_id
  WHERE tr.id = p_reg_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Registration not found'; END IF;
  IF NOT (v_reg.tour_creator = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_reg.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  )) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  UPDATE tournament_registrations SET status = 'confirmed' WHERE id = p_reg_id;
END;
$$;

GRANT EXECUTE ON FUNCTION approve_registration(uuid) TO authenticated;

-- ── reject_registration ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION reject_registration(p_reg_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_reg record;
BEGIN
  SELECT tr.*, t.club_id, t.created_by AS tour_creator
  INTO v_reg FROM tournament_registrations tr
  JOIN tournaments t ON t.id = tr.tournament_id WHERE tr.id = p_reg_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Registration not found'; END IF;
  IF NOT (v_reg.tour_creator = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_reg.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  )) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE tournament_registrations SET status = 'rejected' WHERE id = p_reg_id;
END;
$$;

GRANT EXECUTE ON FUNCTION reject_registration(uuid) TO authenticated;

-- ── withdraw_registration ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION withdraw_registration(p_reg_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_reg record;
BEGIN
  SELECT * INTO v_reg FROM tournament_registrations WHERE id = p_reg_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Registration not found'; END IF;
  IF v_reg.registered_by <> auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE tournament_registrations SET status = 'withdrawn' WHERE id = p_reg_id;
END;
$$;

GRANT EXECUTE ON FUNCTION withdraw_registration(uuid) TO authenticated;

-- ── set_seed ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_seed(p_reg_id uuid, p_seed int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_reg record;
BEGIN
  SELECT tr.*, t.club_id, t.created_by AS tour_creator
  INTO v_reg FROM tournament_registrations tr
  JOIN tournaments t ON t.id = tr.tournament_id WHERE tr.id = p_reg_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Registration not found'; END IF;
  IF NOT (v_reg.tour_creator = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_reg.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  )) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE tournament_registrations SET seed = p_seed WHERE id = p_reg_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_seed(uuid,int) TO authenticated;

-- ── generate_bracket ──────────────────────────────────────────────────
-- Pairing for single elimination: slot i vs slot (padded+1-i).
-- Top seeds get BYEs (they sit in the lower-numbered slots which pair against
-- the higher-numbered BYE slots). BYE winners auto-advance.
CREATE OR REPLACE FUNCTION generate_bracket(p_tournament_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tour      record;
  v_teams     uuid[];
  n           int;
  n_rounds    int;
  padded      int;
  n_matches   int;
  a_slot      int;
  b_slot      int;
  team_a      uuid;
  team_b      uuid;
  is_bye_a    boolean;
  is_bye_b    boolean;
  r           int;
  i           int;
  prev_ids    uuid[];
  curr_ids    uuid[];
  new_id      uuid;
  pos         int;
BEGIN
  SELECT * INTO v_tour FROM tournaments WHERE id = p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;

  IF NOT (v_tour.created_by = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_tour.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  )) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  -- Get confirmed teams sorted by seed
  SELECT array_agg(id ORDER BY COALESCE(seed, 9999), created_at)
  INTO v_teams
  FROM tournament_registrations
  WHERE tournament_id = p_tournament_id AND status = 'confirmed';

  n := COALESCE(array_length(v_teams, 1), 0);
  IF n < 2 THEN RAISE EXCEPTION 'Need at least 2 confirmed teams to generate bracket'; END IF;

  -- Clear existing matches
  DELETE FROM tournament_matches WHERE tournament_id = p_tournament_id;

  -- ── Single Elimination ──────────────────────────────────────────────
  IF v_tour.format = 'single_elimination' THEN
    n_rounds  := GREATEST(1, ceil(log(2, n::float))::int);
    padded    := (2 ^ n_rounds)::int;
    n_matches := padded / 2;
    curr_ids  := '{}';

    -- Round 1: pair slot i vs slot (padded+1-i)
    FOR i IN 1..n_matches LOOP
      a_slot   := i;
      b_slot   := padded + 1 - i;
      is_bye_a := a_slot > n;
      is_bye_b := b_slot > n;
      team_a   := CASE WHEN NOT is_bye_a THEN v_teams[a_slot] ELSE NULL END;
      team_b   := CASE WHEN NOT is_bye_b THEN v_teams[b_slot] ELSE NULL END;

      INSERT INTO tournament_matches (
        tournament_id, round, position,
        team_a_id, team_b_id, status, winner_id
      ) VALUES (
        p_tournament_id, 1, i,
        team_a, team_b,
        CASE WHEN is_bye_a OR is_bye_b THEN 'bye' ELSE 'scheduled' END,
        CASE
          WHEN is_bye_b AND NOT is_bye_a THEN team_a
          WHEN is_bye_a AND NOT is_bye_b THEN team_b
          ELSE NULL
        END
      ) RETURNING id INTO new_id;

      curr_ids := array_append(curr_ids, new_id);
    END LOOP;

    -- Subsequent rounds
    FOR r IN 2..n_rounds LOOP
      prev_ids  := curr_ids;
      n_matches := n_matches / 2;
      curr_ids  := '{}';

      FOR i IN 1..n_matches LOOP
        INSERT INTO tournament_matches (tournament_id, round, position, status)
        VALUES (p_tournament_id, r, i, 'scheduled')
        RETURNING id INTO new_id;

        UPDATE tournament_matches SET next_match_id = new_id, next_match_slot = 'a'
        WHERE id = prev_ids[2*i - 1];
        UPDATE tournament_matches SET next_match_id = new_id, next_match_slot = 'b'
        WHERE id = prev_ids[2*i];

        curr_ids := array_append(curr_ids, new_id);
      END LOOP;
    END LOOP;

    -- Propagate BYE auto-advances (repeat to handle rare chained BYEs)
    FOR r IN 1..4 LOOP
      UPDATE tournament_matches nm
      SET team_a_id = CASE WHEN fm.next_match_slot = 'a' THEN fm.winner_id ELSE nm.team_a_id END,
          team_b_id = CASE WHEN fm.next_match_slot = 'b' THEN fm.winner_id ELSE nm.team_b_id END
      FROM tournament_matches fm
      WHERE fm.tournament_id = p_tournament_id
        AND fm.status = 'bye'
        AND fm.winner_id IS NOT NULL
        AND fm.next_match_id = nm.id
        AND nm.tournament_id = p_tournament_id;

      -- Mark any newly-formed BYE (exactly one team set, other stays NULL)
      UPDATE tournament_matches
      SET status    = 'bye',
          winner_id = COALESCE(team_a_id, team_b_id)
      WHERE tournament_id = p_tournament_id
        AND status = 'scheduled'
        AND ((team_a_id IS NULL) <> (team_b_id IS NULL));   -- XOR
    END LOOP;

  -- ── Round Robin ─────────────────────────────────────────────────────
  ELSIF v_tour.format = 'round_robin' THEN
    pos := 0;
    FOR i IN 1..n LOOP
      FOR r IN (i+1)..n LOOP
        pos := pos + 1;
        INSERT INTO tournament_matches (
          tournament_id, round, position, team_a_id, team_b_id, status
        ) VALUES (p_tournament_id, 1, pos, v_teams[i], v_teams[r], 'scheduled');
      END LOOP;
    END LOOP;

  ELSE
    RAISE EXCEPTION 'Unsupported format: %', v_tour.format;
  END IF;

  -- Set tournament live
  UPDATE tournaments SET status = 'live', updated_at = now()
  WHERE id = p_tournament_id;
END;
$$;

GRANT EXECUTE ON FUNCTION generate_bracket(uuid) TO authenticated;

-- ── record_tournament_result ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION record_tournament_result(
  p_match_id uuid,
  p_score_a  int,
  p_score_b  int
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_match     record;
  v_winner_id uuid;
  v_remaining int;
BEGIN
  SELECT tm.*, t.club_id, t.created_by AS tour_creator, t.format AS tour_format
  INTO v_match
  FROM tournament_matches tm
  JOIN tournaments t ON t.id = tm.tournament_id
  WHERE tm.id = p_match_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF v_match.status = 'completed' THEN RAISE EXCEPTION 'Match already completed'; END IF;
  IF v_match.status = 'bye'       THEN RAISE EXCEPTION 'Cannot record result for a BYE'; END IF;
  IF v_match.team_a_id IS NULL OR v_match.team_b_id IS NULL THEN
    RAISE EXCEPTION 'Both teams must be set before recording a result';
  END IF;

  IF NOT (v_match.tour_creator = auth.uid() OR EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = v_match.club_id AND user_id = auth.uid() AND role IN ('owner','manager')
  )) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  IF p_score_a = p_score_b THEN
    RAISE EXCEPTION 'Scores cannot be equal — there must be a winner';
  END IF;

  v_winner_id := CASE WHEN p_score_a > p_score_b THEN v_match.team_a_id ELSE v_match.team_b_id END;

  UPDATE tournament_matches
  SET score_a = p_score_a, score_b = p_score_b,
      winner_id = v_winner_id, status = 'completed'
  WHERE id = p_match_id;

  -- Advance winner to next match (single elimination)
  IF v_match.next_match_id IS NOT NULL THEN
    IF v_match.next_match_slot = 'a' THEN
      UPDATE tournament_matches SET team_a_id = v_winner_id WHERE id = v_match.next_match_id;
    ELSE
      UPDATE tournament_matches SET team_b_id = v_winner_id WHERE id = v_match.next_match_id;
    END IF;
  ELSE
    -- No next match: check if tournament is complete
    -- For single_elimination this is the final
    -- For round_robin check if all matches are done
    SELECT COUNT(*) INTO v_remaining
    FROM tournament_matches
    WHERE tournament_id = v_match.tournament_id AND status = 'scheduled';

    IF v_remaining = 0 THEN
      UPDATE tournaments
      SET status = 'completed',
          winner_registration_id = CASE WHEN v_match.tour_format = 'single_elimination'
                                        THEN v_winner_id ELSE winner_registration_id END,
          updated_at = now()
      WHERE id = v_match.tournament_id;
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION record_tournament_result(uuid,int,int) TO authenticated;

-- ── get_tournaments ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_tournaments(
  p_club_id  uuid DEFAULT NULL,
  p_status   text DEFAULT NULL,
  p_emirate  text DEFAULT NULL
) RETURNS TABLE (
  id                    uuid,
  club_id               uuid,
  club_name             text,
  name                  text,
  description           text,
  format                text,
  status                text,
  max_teams             int,
  entry_fee             numeric,
  prize_info            text,
  venue                 text,
  emirate               text,
  registration_end      date,
  start_date            date,
  end_date              date,
  confirmed_teams       bigint,
  pending_teams         bigint,
  winner_team_name      text,
  created_by            uuid,
  created_at            timestamptz
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id, t.club_id, c.name AS club_name,
    t.name, t.description, t.format, t.status,
    t.max_teams, t.entry_fee, t.prize_info, t.venue, t.emirate,
    t.registration_end, t.start_date, t.end_date,
    (SELECT COUNT(*) FROM tournament_registrations r
     WHERE r.tournament_id = t.id AND r.status = 'confirmed') AS confirmed_teams,
    (SELECT COUNT(*) FROM tournament_registrations r
     WHERE r.tournament_id = t.id AND r.status = 'pending')   AS pending_teams,
    (SELECT tr.team_name FROM tournament_registrations tr
     WHERE tr.id = t.winner_registration_id)               AS winner_team_name,
    t.created_by, t.created_at
  FROM tournaments t
  JOIN clubs c ON c.id = t.club_id
  WHERE (p_club_id IS NULL OR t.club_id = p_club_id)
    AND (p_status  IS NULL OR t.status  = p_status)
    AND (p_emirate IS NULL OR t.emirate = p_emirate)
  ORDER BY
    CASE t.status
      WHEN 'live'              THEN 1
      WHEN 'registration_open' THEN 2
      WHEN 'completed'         THEN 3
      ELSE 4
    END,
    t.start_date DESC NULLS LAST,
    t.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_tournaments(uuid,text,text) TO anon, authenticated;

-- ── get_tournament_detail ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_tournament_detail(p_tournament_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tournament', to_jsonb(t) || jsonb_build_object(
      'club_name', c.name,
      'winner_team_name', wr.team_name
    ),
    'registrations', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', tr.id, 'team_name', tr.team_name,
          'player_a_name', tr.player_a_name, 'player_b_name', tr.player_b_name,
          'status', tr.status, 'seed', tr.seed,
          'registered_by', tr.registered_by, 'created_at', tr.created_at
        ) ORDER BY COALESCE(tr.seed, 9999), tr.created_at
      )
      FROM tournament_registrations tr
      WHERE tr.tournament_id = p_tournament_id
        AND tr.status IN ('pending','confirmed')
    ), '[]'),
    'matches', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', tm.id, 'round', tm.round, 'position', tm.position,
          'team_a_id', tm.team_a_id, 'team_a_name', ta.team_name,
          'team_b_id', tm.team_b_id, 'team_b_name', tb.team_name,
          'score_a', tm.score_a, 'score_b', tm.score_b,
          'winner_id', tm.winner_id, 'winner_name', tw.team_name,
          'status', tm.status,
          'next_match_id', tm.next_match_id,
          'next_match_slot', tm.next_match_slot,
          'scheduled_at', tm.scheduled_at
        ) ORDER BY tm.round, tm.position
      )
      FROM tournament_matches tm
      LEFT JOIN tournament_registrations ta ON ta.id = tm.team_a_id
      LEFT JOIN tournament_registrations tb ON tb.id = tm.team_b_id
      LEFT JOIN tournament_registrations tw ON tw.id = tm.winner_id
      WHERE tm.tournament_id = p_tournament_id
    ), '[]'),
    'standings', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'registration_id', vs.registration_id,
          'team_name', vs.team_name,
          'seed', vs.seed,
          'wins', vs.wins, 'losses', vs.losses, 'played', vs.played,
          'sets_for', vs.sets_for, 'sets_against', vs.sets_against
        ) ORDER BY vs.wins DESC, (vs.sets_for - vs.sets_against) DESC
      )
      FROM v_tournament_standings vs
      WHERE vs.tournament_id = p_tournament_id
    ), '[]')
  ) INTO v_result
  FROM tournaments t
  JOIN clubs c ON c.id = t.club_id
  LEFT JOIN tournament_registrations wr ON wr.id = t.winner_registration_id
  WHERE t.id = p_tournament_id;

  IF v_result IS NULL THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_tournament_detail(uuid) TO anon, authenticated;
