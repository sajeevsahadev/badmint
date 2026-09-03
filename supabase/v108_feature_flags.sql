-- v108_feature_flags
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- ═══════════════════════════════════════════════════════════════════════
-- v108: Runtime feature flags, toggled by app admins from the Admin Panel.
-- Replaces the build-time TOURNAMENTS_ENABLED constant so tournaments can be
-- turned on/off without a redeploy.
-- ═══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.app_settings (
  key         text PRIMARY KEY,
  enabled     boolean NOT NULL DEFAULT false,
  updated_at  timestamptz DEFAULT now(),
  updated_by  uuid
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
-- No direct policies: all access goes through the SECURITY DEFINER RPCs below.

-- Enable tournaments now (per product decision); admins can toggle it hereafter.
INSERT INTO public.app_settings (key, enabled) VALUES ('tournaments_enabled', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;

-- Read all flags as a { key: bool } object (public — the app reads this on boot).
CREATE OR REPLACE FUNCTION public.get_app_settings()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_object_agg(key, enabled), '{}'::jsonb) FROM app_settings;
$$;
GRANT EXECUTE ON FUNCTION public.get_app_settings() TO anon, authenticated;

-- Toggle a flag (app admins only).
CREATE OR REPLACE FUNCTION public.set_feature_flag(p_key text, p_enabled boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  INSERT INTO app_settings (key, enabled, updated_at, updated_by)
  VALUES (p_key, p_enabled, now(), auth.uid())
  ON CONFLICT (key) DO UPDATE
    SET enabled = EXCLUDED.enabled, updated_at = now(), updated_by = auth.uid();
END;$$;
GRANT EXECUTE ON FUNCTION public.set_feature_flag(text, boolean) TO authenticated;;
