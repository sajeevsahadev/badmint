-- =====================================================================
-- Badminton 360 v127 — Soft-delete clubs with 30-day retention
-- Applied to prod via Supabase MCP; archived here for rebuild parity.
--
-- Admin "delete club" no longer CASCADE-destroys the club. It sets
-- clubs.deleted_at; the club + all its data are hidden everywhere and can be
-- restored for 30 days, after which a daily pg_cron job hard-deletes them.
--
-- Keystone: the clubs SELECT RLS policy now also requires deleted_at IS NULL,
-- so a deleted club's row vanishes from every RLS-governed read. The public
-- SECURITY DEFINER read functions (which bypass RLS) add an explicit filter.
-- useClub.loadClubs uses clubs!inner so deleted clubs drop from member lists.
-- =====================================================================

ALTER TABLE clubs ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
CREATE INDEX IF NOT EXISTS idx_clubs_deleted_at ON clubs(deleted_at) WHERE deleted_at IS NOT NULL;

DROP POLICY IF EXISTS clubs_read ON clubs;
CREATE POLICY clubs_read ON clubs FOR SELECT USING (is_member(id) AND deleted_at IS NULL);

CREATE OR REPLACE FUNCTION admin_delete_club(p_club_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  UPDATE clubs SET deleted_at = now() WHERE id = p_club_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Club not found or already deleted'; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION admin_delete_club(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION admin_restore_club(p_club_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  UPDATE clubs SET deleted_at = NULL WHERE id = p_club_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Club not found'; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION admin_restore_club(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION admin_purge_club(p_club_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  DELETE FROM clubs WHERE id = p_club_id;   -- hard CASCADE delete
END; $$;
GRANT EXECUTE ON FUNCTION admin_purge_club(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION admin_get_deleted_clubs()
RETURNS TABLE(club_id uuid, name text, deleted_at timestamptz, days_left int, member_count bigint, owner_email text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  SELECT c.id, c.name, c.deleted_at,
    GREATEST(0, 30 - floor(EXTRACT(epoch FROM now() - c.deleted_at)/86400)::int),
    (SELECT count(*) FROM club_members cm WHERE cm.club_id = c.id),
    (SELECT au.email::text FROM auth.users au WHERE au.id = c.created_by)
  FROM clubs c WHERE c.deleted_at IS NOT NULL
  ORDER BY c.deleted_at DESC;
END; $$;
GRANT EXECUTE ON FUNCTION admin_get_deleted_clubs() TO authenticated;

-- admin_get_clubs / get_public_clubs / get_club_ranking / get_top_scorers /
-- get_tournaments recreated identically with an added "deleted_at IS NULL"
-- filter on the joined clubs row. (See migration source; bodies unchanged
-- except that filter.)

-- Daily purge of clubs soft-deleted more than 30 days ago.
SELECT cron.schedule('purge-deleted-clubs', '30 3 * * *', $PURGE$
  DELETE FROM clubs WHERE deleted_at IS NOT NULL AND deleted_at < now() - interval '30 days';
$PURGE$);
