-- v75_schedule_time_slots
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Time-slot support: a match day can have multiple slots (separate rows),
-- each with its own start/end time and an optional attendee cap.
ALTER TABLE club_schedule ADD COLUMN IF NOT EXISTS start_time    time;
ALTER TABLE club_schedule ADD COLUMN IF NOT EXISTS end_time      time;
ALTER TABLE club_schedule ADD COLUMN IF NOT EXISTS max_attendees int NOT NULL DEFAULT 0;  -- 0 = unlimited

COMMENT ON COLUMN club_schedule.max_attendees IS '0 = unlimited; otherwise first N ''attending'' voters (by voted_at) are Present, rest are Bench';;
