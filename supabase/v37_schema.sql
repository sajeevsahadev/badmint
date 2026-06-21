-- v37: pg_cron schedule for weekly ranking digest email
-- ──────────────────────────────────────────────────────────────────────────
-- Prerequisites:
--   • pg_cron extension must be enabled in your Supabase project
--     (Database → Extensions → pg_cron)
--   • pg_net extension must be enabled (Database → Extensions → pg_net)
--   • The send-weekly-digest Edge Function must be deployed:
--       supabase functions deploy send-weekly-digest
--
-- Before running this script, replace the two placeholders below:
--   YOUR_PROJECT_REF  → your Supabase project ref (e.g. abcdefghijklmnop)
--                       Found at: Supabase Dashboard → Project Settings → General
--   YOUR_SERVICE_ROLE_KEY → your service_role secret key
--                       Found at: Supabase Dashboard → Project Settings → API
--
-- IMPORTANT: The service role key is a secret. Do NOT commit this file to
-- version control after filling in the real values. Run it in the Supabase
-- SQL Editor and leave the placeholders in the committed version.
-- ──────────────────────────────────────────────────────────────────────────

SELECT cron.schedule(
  'weekly-ranking-digest',          -- job name (unique; use cron.unschedule() to remove)
  '0 8 * * 1',                      -- every Monday at 08:00 UTC
  $$
  SELECT net.http_post(
    url     := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-weekly-digest',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb,
    body    := '{}'::jsonb
  );
  $$
);

-- To verify the job was created:
-- SELECT * FROM cron.job WHERE jobname = 'weekly-ranking-digest';

-- To remove the schedule:
-- SELECT cron.unschedule('weekly-ranking-digest');
