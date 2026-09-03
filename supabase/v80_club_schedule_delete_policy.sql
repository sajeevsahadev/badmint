-- v80_club_schedule_delete_policy
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- club_schedule had INSERT/SELECT/UPDATE policies but NO DELETE policy, so
-- "Cancel this event" deleted zero rows (RLS-filtered, no error) and the event
-- silently reappeared. Allow the creator or an owner/manager to delete.
DROP POLICY IF EXISTS cs_member_delete ON club_schedule;
CREATE POLICY cs_member_delete ON club_schedule FOR DELETE
USING (
  created_by = auth.uid()
  OR EXISTS (
    SELECT 1 FROM club_members cm
    WHERE cm.club_id = club_schedule.club_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('owner','manager')
  )
);;
