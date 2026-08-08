-- =====================================================================
-- Badminton 360 v60 — helper for invite push notifications
-- Run in Supabase SQL Editor (after v59_schema.sql).
--
-- notify-invite needs to turn an invited email into a user_id so it can
-- push existing B360 users. Reading auth.users requires elevated rights,
-- so this is a SECURITY DEFINER lookup. It returns NULL for emails that
-- don't have an account yet (those people only get the email/link).
-- =====================================================================

CREATE OR REPLACE FUNCTION resolve_user_id_by_email(p_email text)
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
  SELECT id FROM auth.users
  WHERE lower(email) = lower(trim(p_email))
  LIMIT 1;
$$;

-- Only the Edge Function (service_role) needs this. Do NOT expose to anon
-- or ordinary authenticated clients — it would leak email → account existence.
REVOKE EXECUTE ON FUNCTION resolve_user_id_by_email(text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION resolve_user_id_by_email(text) TO service_role;
