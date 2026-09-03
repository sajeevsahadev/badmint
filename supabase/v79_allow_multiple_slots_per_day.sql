-- v79_allow_multiple_slots_per_day
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- v79: A match day can hold multiple time-slot sessions.
-- The old UNIQUE(club_id, scheduled_date) blocked a second slot on the same
-- day (insert failed → the venue picker got stuck). Drop it.
ALTER TABLE club_schedule
  DROP CONSTRAINT IF EXISTS club_schedule_club_id_scheduled_date_key;

-- The legacy create_schedule() RPC relied on that constraint via ON CONFLICT.
-- It's unused by the app (Schedule.vue inserts directly), but rewrite it to a
-- plain insert so it can never error on the missing constraint.
CREATE OR REPLACE FUNCTION public.create_schedule(
  p_club_id uuid, p_date date,
  p_facility_id uuid DEFAULT NULL, p_facility_name text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;

  INSERT INTO club_schedule(club_id, scheduled_date, facility_id, facility_name, created_by)
  VALUES (p_club_id, p_date, p_facility_id, p_facility_name, auth.uid())
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;;
