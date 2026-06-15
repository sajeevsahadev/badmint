-- =====================================================================
-- Badmint v30 — facilities: add courts_count column, drop UAE-only emirate check
-- Run once in Supabase SQL Editor
-- =====================================================================

-- Add courts_count column that admin_get_facilities / admin_update_facility
-- reference but was never created in v6_schema.sql
ALTER TABLE facilities ADD COLUMN IF NOT EXISTS courts_count int;

-- Drop the UAE-only emirate check constraint — the app is now global (B360
-- rebrand). The emirate column is free-text city/region for any country.
ALTER TABLE facilities DROP CONSTRAINT IF EXISTS facilities_emirate_check;
