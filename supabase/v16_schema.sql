-- =====================================================================
-- Badmint v16 — delete_club RPC + fix get_tournaments ambiguous column
-- Run in Supabase SQL Editor after v15_schema.sql
-- =====================================================================

-- ── Fix get_tournaments: ambiguous "status" in subqueries (v14 bug) ───
-- tournament_registrations subqueries used bare `status` which PostgreSQL
-- couldn't resolve against the outer RETURNS TABLE's `status` column.
-- Fix: alias the subquery table as `r` and qualify every column.
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
     WHERE tr.id = t.winner_registration_id)                  AS winner_team_name,
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

-- ── delete_club ───────────────────────────────────────────────────────
-- Only the club owner can call this.
-- Blocks if any matches exist → user must delete all matches first.
-- Cleans up paysplit data, schedule, tournaments, and all club rows
-- automatically via ON DELETE CASCADE on the clubs table.
CREATE OR REPLACE FUNCTION delete_club(p_club_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role        text;
  v_match_count int;
  v_club_name   text;
BEGIN
  -- Must be the owner
  SELECT cm.role, c.name INTO v_role, v_club_name
  FROM club_members cm
  JOIN clubs c ON c.id = cm.club_id
  WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid();

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'You are not a member of this club';
  END IF;
  IF v_role <> 'owner' THEN
    RAISE EXCEPTION 'Only the club owner can delete this club';
  END IF;

  -- Block if any matches recorded
  SELECT COUNT(*) INTO v_match_count FROM matches WHERE club_id = p_club_id;
  IF v_match_count > 0 THEN
    RAISE EXCEPTION 'MATCH_COUNT:% — Delete all % match(es) from the Matches page first.',
      v_match_count, v_match_count;
  END IF;

  -- Delete club — CASCADE removes:
  --   club_members, ranking_config, players, attendance, join_requests,
  --   club_invites, facility_bookings, paysplit_expenses (→ paysplit_participants),
  --   paysplit_notes, wallet_contributions, playing_schedule,
  --   push_subscriptions, tournaments
  DELETE FROM clubs WHERE id = p_club_id;

  RETURN jsonb_build_object('deleted', true, 'club_name', v_club_name);
END;
$$;

GRANT EXECUTE ON FUNCTION delete_club(uuid) TO authenticated;
