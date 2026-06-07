-- =====================================================================
-- Badmint v17 — delete_tournament RPC
-- Run in Supabase SQL Editor after v16_schema.sql
-- =====================================================================

-- ── delete_tournament ─────────────────────────────────────────────────
-- Allowed: tournament creator, club owner/manager, app_admin.
-- CASCADE removes tournament_registrations and tournament_matches.
CREATE OR REPLACE FUNCTION delete_tournament(p_tournament_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tour tournaments%ROWTYPE;
BEGIN
  SELECT * INTO v_tour FROM tournaments WHERE id = p_tournament_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tournament not found';
  END IF;

  IF NOT (
    v_tour.created_by = auth.uid()
    OR is_app_admin()
    OR EXISTS (
      SELECT 1 FROM club_members
      WHERE club_id = v_tour.club_id
        AND user_id  = auth.uid()
        AND role IN ('owner','manager')
    )
  ) THEN
    RAISE EXCEPTION 'Only the tournament creator or a club owner/manager can delete this tournament';
  END IF;

  DELETE FROM tournaments WHERE id = p_tournament_id;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_tournament(uuid) TO authenticated;
