-- =====================================================================
-- Badminton 360 v54 — Per-club weekly digest schedule
-- Run in Supabase SQL Editor. (Already applied to prod.)
--
-- v53 sent the digest to every club at one fixed time (Sun 14:00 UTC).
-- Owners want to choose their club's day + time. We store a per-club
-- day-of-week + hour + timezone, run the cron HOURLY, and have the Edge
-- Function send only to clubs whose local (tz) day+hour matches "now".
--
-- Default: Sunday 21:00 (9 PM) in the club's timezone (default Asia/Dubai).
-- =====================================================================

-- ── 1. Per-club schedule columns ────────────────────────────────────
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS digest_dow  int  NOT NULL DEFAULT 0;   -- 0=Sun … 6=Sat
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS digest_hour int  NOT NULL DEFAULT 21;  -- 0..23 (21 = 9 PM)
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS digest_tz   text NOT NULL DEFAULT 'Asia/Dubai';
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS digest_enabled boolean NOT NULL DEFAULT true;

-- ── 2. RPC: owner/manager sets the schedule ─────────────────────────
CREATE OR REPLACE FUNCTION set_club_digest_schedule(
  p_club_id uuid,
  p_dow     int,
  p_hour    int,
  p_tz      text DEFAULT 'Asia/Dubai',
  p_enabled boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_manager(p_club_id) THEN
    RAISE EXCEPTION 'Only club managers or owners can change the digest schedule';
  END IF;
  IF p_dow  < 0 OR p_dow  > 6  THEN RAISE EXCEPTION 'Day must be 0..6'; END IF;
  IF p_hour < 0 OR p_hour > 23 THEN RAISE EXCEPTION 'Hour must be 0..23'; END IF;
  -- Validate the timezone name (now()::timestamptz AT TIME ZONE throws on bad tz)
  PERFORM now() AT TIME ZONE COALESCE(NULLIF(trim(p_tz), ''), 'Asia/Dubai');

  UPDATE clubs SET
    digest_dow     = p_dow,
    digest_hour    = p_hour,
    digest_tz      = COALESCE(NULLIF(trim(p_tz), ''), 'Asia/Dubai'),
    digest_enabled = p_enabled
  WHERE id = p_club_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_club_digest_schedule(uuid, int, int, text, boolean) TO authenticated;

-- ── 2b. RPC: manager-triggered "Send test now" for one club ─────────
-- Fires the digest Edge Function via pg_net (async), passing the Vault
-- secret + force+club_id so the caller never needs the secret.
CREATE OR REPLACE FUNCTION trigger_club_digest(p_club_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_manager(p_club_id) THEN
    RAISE EXCEPTION 'Only club managers or owners can send the digest';
  END IF;
  PERFORM net.http_post(
    url     := 'https://bdmiirppiyopmdfrztoz.supabase.co/functions/v1/send-weekly-digest',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'weekly_digest_secret')
    ),
    body    := jsonb_build_object('force', true, 'club_id', p_club_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION trigger_club_digest(uuid) TO authenticated;

-- ── 3. Re-point the cron to run HOURLY ──────────────────────────────
-- The Edge Function decides, per club, whether its local day+hour is "now".
SELECT cron.unschedule('weekly-ranking-digest')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-ranking-digest');

SELECT cron.schedule(
  'weekly-ranking-digest',
  '0 * * * *',   -- top of every hour
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
