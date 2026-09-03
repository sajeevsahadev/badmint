-- v97_trigger_digest_managers_only
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Manager-triggered digest send. p_managers_only=true sends a test only to the
-- club's owners/managers (bypassing opt-in); false sends to all opted-in members.
CREATE OR REPLACE FUNCTION public.trigger_club_digest(
  p_club_id uuid,
  p_managers_only boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
    body    := jsonb_build_object('force', true, 'club_id', p_club_id, 'managers_only', p_managers_only)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.trigger_club_digest(uuid, boolean) TO authenticated;;
