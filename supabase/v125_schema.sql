-- =====================================================================
-- Badminton 360 v125 — Onboarding email lifecycle (welcome + no-club nudges)
-- Run in Supabase SQL Editor. (Applied to prod.)
--
-- Sends, fully automated via a daily pg_cron job (see v125_cron.sql) that calls
-- the send-lifecycle-emails Edge Function:
--   • welcome  — to brand-new signups (created in the last 2 days), once
--   • day2     — 2–30 days after signup if still no club, once
--   • monthly  — 30+ days in if still no club, at most once per 30 days
-- Every send is recorded in lifecycle_email_log so nothing ever repeats, and
-- the nudges respect email_prefs.news. Only new signups can get 'welcome', so
-- existing users are never mass-mailed.
-- =====================================================================

CREATE TABLE IF NOT EXISTS lifecycle_email_log (
  id      bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind    text NOT NULL,                 -- 'welcome' | 'day2' | 'monthly'
  sent_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lifecycle_log_user_kind ON lifecycle_email_log(user_id, kind, sent_at DESC);
ALTER TABLE lifecycle_email_log ENABLE ROW LEVEL SECURITY;
-- No public policies: only SECURITY DEFINER RPCs (and the service role) touch it.

-- Optional immediate-welcome hook (currently unused; the dispatcher handles
-- welcome server-side). Kept for a future in-app "welcome me now" path.
CREATE OR REPLACE FUNCTION claim_welcome_email()
RETURNS TABLE(email text, name text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  INSERT INTO lifecycle_email_log(user_id, kind)
  SELECT v_uid, 'welcome'
  WHERE NOT EXISTS (SELECT 1 FROM lifecycle_email_log l WHERE l.user_id = v_uid AND l.kind = 'welcome');
  IF NOT FOUND THEN RETURN; END IF;
  RETURN QUERY
  SELECT u.email::text, COALESCE(up.full_name, up.nickname, split_part(u.email, '@', 1))
  FROM auth.users u LEFT JOIN user_profiles up ON up.user_id = u.id
  WHERE u.id = v_uid;
END;
$$;
GRANT EXECUTE ON FUNCTION claim_welcome_email() TO authenticated;

-- Users due a lifecycle email. Service-role only (called by the dispatcher).
CREATE OR REPLACE FUNCTION get_pending_nudges()
RETURNS TABLE(user_id uuid, email text, name text, kind text)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  -- Welcome: signed up in the last 2 days, not yet welcomed (any club status)
  SELECT u.id, u.email::text,
         COALESCE(up.full_name, up.nickname, split_part(u.email, '@', 1)), 'welcome'::text
  FROM auth.users u
  LEFT JOIN user_profiles up ON up.user_id = u.id
  WHERE u.email IS NOT NULL
    AND u.created_at > now() - interval '2 days'
    AND NOT EXISTS (SELECT 1 FROM lifecycle_email_log l WHERE l.user_id = u.id AND l.kind = 'welcome')
  UNION ALL
  -- Day-2: signed up 2–30 days ago, still no club, not yet sent
  SELECT u.id, u.email::text,
         COALESCE(up.full_name, up.nickname, split_part(u.email, '@', 1)), 'day2'::text
  FROM auth.users u
  LEFT JOIN user_profiles up ON up.user_id = u.id
  WHERE u.email IS NOT NULL
    AND u.created_at <= now() - interval '2 days'
    AND u.created_at >  now() - interval '30 days'
    AND COALESCE((up.email_prefs->>'news')::boolean, true)
    AND NOT EXISTS (SELECT 1 FROM club_members cm WHERE cm.user_id = u.id)
    AND NOT EXISTS (SELECT 1 FROM lifecycle_email_log l WHERE l.user_id = u.id AND l.kind = 'day2')
  UNION ALL
  -- Monthly: 30+ days in, still no club, not nudged in the last 30 days
  SELECT u.id, u.email::text,
         COALESCE(up.full_name, up.nickname, split_part(u.email, '@', 1)), 'monthly'::text
  FROM auth.users u
  LEFT JOIN user_profiles up ON up.user_id = u.id
  WHERE u.email IS NOT NULL
    AND u.created_at <= now() - interval '30 days'
    AND COALESCE((up.email_prefs->>'news')::boolean, true)
    AND NOT EXISTS (SELECT 1 FROM club_members cm WHERE cm.user_id = u.id)
    AND NOT EXISTS (SELECT 1 FROM lifecycle_email_log l
                    WHERE l.user_id = u.id AND l.kind = 'monthly' AND l.sent_at > now() - interval '30 days')
  LIMIT 800;
$$;
REVOKE ALL ON FUNCTION get_pending_nudges() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION get_pending_nudges() TO service_role;

CREATE OR REPLACE FUNCTION log_lifecycle_email(p_user_id uuid, p_kind text)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$ INSERT INTO lifecycle_email_log(user_id, kind) VALUES (p_user_id, p_kind); $$;
REVOKE ALL ON FUNCTION log_lifecycle_email(uuid, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION log_lifecycle_email(uuid, text) TO service_role;
