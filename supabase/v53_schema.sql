-- =====================================================================
-- Badminton 360 v53 — Weekly ranking digest: automated Sunday send
-- Run in Supabase SQL Editor. (Already applied to prod.)
--
-- Background: v37 intended to schedule the weekly digest via pg_cron, but
-- pg_cron was never enabled and the job was never created, so no digest
-- ever went out. This migration enables pg_cron and schedules the
-- send-weekly-digest Edge Function for Sunday evening.
--
-- Auth model: send-weekly-digest is deployed with verify_jwt = false and
-- authenticates callers with a shared secret (env WEEKLY_DIGEST_SECRET on
-- the function; same value stored in Vault as 'weekly_digest_secret'). The
-- cron command reads the secret from Vault at run time, so it is never
-- written into the cron.job command text.
--
-- Prereqs done out-of-band (not re-runnable from SQL):
--   1. supabase secrets set WEEKLY_DIGEST_SECRET=<random>
--   2. supabase functions deploy send-weekly-digest --no-verify-jwt
-- =====================================================================

-- ── 1. Extensions ────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_cron;   -- pg_net is already enabled

-- ── 2. Store the shared secret in Vault (run once; replace the value) ─
-- The real value also lives in the Edge Function env (WEEKLY_DIGEST_SECRET).
-- DO NOT commit the real secret; this is a placeholder.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'weekly_digest_secret') THEN
    PERFORM vault.create_secret('REPLACE_WITH_WEEKLY_DIGEST_SECRET', 'weekly_digest_secret');
  END IF;
END $$;

-- ── 3. Schedule: Sunday 14:00 UTC = 18:00 Gulf (UTC+4) / 19:30 IST ────
SELECT cron.unschedule('weekly-ranking-digest')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-ranking-digest');

SELECT cron.schedule(
  'weekly-ranking-digest',
  '0 14 * * 0',
  $CRON$
  SELECT net.http_post(
    url     := 'https://bdmiirppiyopmdfrztoz.supabase.co/functions/v1/send-weekly-digest',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'weekly_digest_secret')
    ),
    body    := '{}'::jsonb
  );
  $CRON$
);

-- Verify: SELECT jobname, schedule, active FROM cron.job;
-- History: SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 5;
