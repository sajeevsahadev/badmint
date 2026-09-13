-- =====================================================================
-- Badminton 360 v125 cron — daily onboarding email lifecycle
-- Run in Supabase SQL Editor AFTER v125_schema.sql and after deploying the
-- send-lifecycle-emails Edge Function. (Applied to prod.)
--
-- Requires pg_cron + pg_net (already enabled on this project). The bearer below
-- is the project's PUBLISHABLE (anon) key — it is public (it already ships in
-- the client bundle), and it satisfies the function's verify_jwt gate. Replace
-- YOUR_PUBLISHABLE_KEY with the value from Dashboard → Project Settings → API
-- ("publishable"/anon key) before running.
-- =====================================================================

SELECT cron.schedule(
  'lifecycle-nudges',
  '0 9 * * *',                          -- every day at 09:00 UTC
  $CRON$
  SELECT net.http_post(
    url     := 'https://bdmiirppiyopmdfrztoz.supabase.co/functions/v1/send-lifecycle-emails',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_PUBLISHABLE_KEY',
      'apikey', 'YOUR_PUBLISHABLE_KEY'
    ),
    body := '{}'::jsonb
  );
  $CRON$
);

-- Verify:      SELECT * FROM cron.job WHERE jobname = 'lifecycle-nudges';
-- Remove:      SELECT cron.unschedule('lifecycle-nudges');
-- Manual dry-run (no emails):  POST …/functions/v1/send-lifecycle-emails?dry=1
