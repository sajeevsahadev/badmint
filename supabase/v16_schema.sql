-- =====================================================================
-- Badmint v16 — delete_club RPC
-- Run in Supabase SQL Editor after v15_schema.sql
-- =====================================================================

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
