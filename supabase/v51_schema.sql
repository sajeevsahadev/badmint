-- =====================================================================
-- Badminton 360 v51 — Club owners missing from roster
-- Run in Supabase SQL Editor (after v50_schema.sql).
--
-- Bug: create_club() inserted the clubs row, a club_members('owner') row,
-- and ranking_config — but NEVER a players row for the creator. The app's
-- roster (matches, leaderboard, Split Pay expense picker) reads the
-- `players` table, so the club owner was invisible everywhere a player is
-- selected. Reported: in "3S world" the owner (Sandeep) couldn't be picked
-- when adding an expense.
--
-- Invariant this restores: every club_member has a matching players row.
--
-- Fix 1: create_club also creates a players row for the creator.
-- Fix 2: backfill players rows for ALL existing club_members that lack one
--        (repairs every club owner created before this migration).
-- =====================================================================

-- ── Fix 1: create_club creates the owner's player row ────────────────
CREATE OR REPLACE FUNCTION create_club(p_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id   uuid;
  v_name text;
BEGIN
  INSERT INTO clubs(name, created_by) VALUES (p_name, auth.uid()) RETURNING id INTO v_id;
  INSERT INTO club_members(club_id, user_id, role) VALUES (v_id, auth.uid(), 'owner');
  INSERT INTO ranking_config(club_id) VALUES (v_id);

  -- Roster row for the creator so they appear in matches / leaderboard / Split Pay
  SELECT COALESCE(nickname, full_name) INTO v_name
  FROM user_profiles WHERE user_id = auth.uid();

  INSERT INTO players(club_id, user_id, display_name)
  VALUES (v_id, auth.uid(), COALESCE(NULLIF(trim(v_name), ''), 'Player'));

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_club(text) TO authenticated;

-- ── Fix 2: backfill player rows for members that have none ───────────
-- Every club_member should have a players row. Create one wherever it's
-- missing (owners created before this migration, chiefly). display_name
-- uses nickname > full_name > 'Player' (never email — display_name is public).
INSERT INTO players(club_id, user_id, display_name, is_active, elo)
SELECT cm.club_id,
       cm.user_id,
       COALESCE(NULLIF(trim(up.nickname), ''), NULLIF(trim(up.full_name), ''), 'Player'),
       true,
       COALESCE((SELECT starting_elo FROM ranking_config rc WHERE rc.club_id = cm.club_id), 1000)
FROM club_members cm
LEFT JOIN user_profiles up ON up.user_id = cm.user_id
WHERE NOT EXISTS (
  SELECT 1 FROM players p
  WHERE p.club_id = cm.club_id AND p.user_id = cm.user_id
);
