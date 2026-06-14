-- =====================================================================
-- Badmint v24 — delete_join_request RPC (managers can remove rejected requests)
-- Run once in Supabase SQL Editor
-- =====================================================================

CREATE OR REPLACE FUNCTION delete_join_request(p_request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Only managers/owners of the relevant club may delete
  IF NOT EXISTS (
    SELECT 1 FROM join_requests jr
    JOIN club_members cm ON cm.club_id = jr.club_id
    WHERE jr.id = p_request_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('owner', 'manager')
  ) THEN
    RAISE EXCEPTION 'Only club managers and owners can delete join requests';
  END IF;

  DELETE FROM join_requests WHERE id = p_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_join_request(uuid) TO authenticated;
