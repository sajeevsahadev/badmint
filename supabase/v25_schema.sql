-- =====================================================================
-- Badmint v25 — DB-level guard: club must always have at least one owner
-- Run once in Supabase SQL Editor
-- =====================================================================

CREATE OR REPLACE FUNCTION check_club_has_owner()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Only fires when downgrading an owner to a non-owner role
  IF OLD.role = 'owner' AND NEW.role != 'owner' THEN
    -- Count owners OTHER than the row being changed
    IF (
      SELECT COUNT(*) FROM club_members
      WHERE club_id = NEW.club_id
        AND role    = 'owner'
        AND user_id != NEW.user_id
    ) = 0 THEN
      RAISE EXCEPTION 'Club must have at least one owner. Promote another member to Owner first.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_club_has_owner ON club_members;
CREATE TRIGGER trg_check_club_has_owner
  BEFORE UPDATE ON club_members
  FOR EACH ROW EXECUTE FUNCTION check_club_has_owner();
