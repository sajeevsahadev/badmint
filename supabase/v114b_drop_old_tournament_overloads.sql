-- v114b_drop_old_tournament_overloads
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- The new create_tournament / update_tournament_details (v114) added params, so
-- the older overloads still linger and make calls ambiguous. Drop them.
DROP FUNCTION IF EXISTS public.create_tournament(
  uuid, text, text, integer, text, numeric, text, text, text, text, date, date, date,
  integer, boolean, text, integer, integer);
DROP FUNCTION IF EXISTS public.update_tournament_details(
  uuid, text, text, numeric, text, text, text, text, date, date, date, integer, text,
  integer, boolean, text, integer, integer);;
