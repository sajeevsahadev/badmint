-- v120_club_slugs
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- ═══════════════════════════════════════════════════════════════════════
-- v120: human-friendly club join links (/join/saturday-badminton-club).
-- On a name collision, fall back to region, then creation year, then a counter.
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE public.clubs ADD COLUMN IF NOT EXISTS slug text;

CREATE OR REPLACE FUNCTION public._unique_club_slug(p_name text, p_region text, p_created timestamptz, p_id uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE base text := left(_slugify(p_name), 60); cand text; i int := 1;
  cands text[];
BEGIN
  cands := ARRAY[base];
  IF COALESCE(trim(p_region),'') <> '' THEN cands := cands || (base || '-' || _slugify(p_region)); END IF;
  cands := cands || (base || '-' || to_char(COALESCE(p_created, now()), 'YYYY'));
  FOREACH cand IN ARRAY cands LOOP
    IF NOT EXISTS (SELECT 1 FROM clubs WHERE slug = cand AND id <> COALESCE(p_id,'00000000-0000-0000-0000-000000000000')) THEN
      RETURN cand;
    END IF;
  END LOOP;
  -- Everything meaningful is taken → append a counter to the base.
  cand := base;
  WHILE EXISTS (SELECT 1 FROM clubs WHERE slug = cand AND id <> COALESCE(p_id,'00000000-0000-0000-0000-000000000000')) LOOP
    i := i + 1; cand := base || '-' || i;
  END LOOP;
  RETURN cand;
END;$$;

CREATE OR REPLACE FUNCTION public._set_club_slug()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.slug IS NULL THEN NEW.slug := _unique_club_slug(NEW.name, NEW.emirates, NEW.created_at, NEW.id); END IF;
  RETURN NEW;
END;$$;
DROP TRIGGER IF EXISTS trg_set_club_slug ON public.clubs;
CREATE TRIGGER trg_set_club_slug BEFORE INSERT ON public.clubs
  FOR EACH ROW EXECUTE FUNCTION _set_club_slug();

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id, name, emirates, created_at FROM clubs WHERE slug IS NULL ORDER BY created_at LOOP
    UPDATE clubs SET slug = _unique_club_slug(r.name, r.emirates, r.created_at, r.id) WHERE id = r.id;
  END LOOP;
END$$;
CREATE UNIQUE INDEX IF NOT EXISTS clubs_slug_key ON public.clubs(slug);

-- Resolve a public club by slug OR uuid (join link). Returns the club row the
-- JoinClub page needs, including the real id + slug.
DROP FUNCTION IF EXISTS public.get_public_club_by_id(uuid);
CREATE OR REPLACE FUNCTION public.get_public_club_by_id(p_club_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid; v jsonb;
BEGIN
  SELECT id INTO v_id FROM clubs WHERE slug = p_club_id OR id::text = p_club_id LIMIT 1;
  IF v_id IS NULL THEN RETURN NULL; END IF;
  SELECT jsonb_build_object(
    'id', c.id, 'slug', c.slug, 'name', c.name, 'emirates', c.emirates,
    'facility_name', c.facility_name, 'facility_address', c.facility_address,
    'description', c.description, 'join_policy', c.join_policy,
    'member_count', (SELECT count(*) FROM club_members m WHERE m.club_id = c.id)
  ) INTO v FROM clubs c WHERE c.id = v_id;
  RETURN v;
END;$$;
GRANT EXECUTE ON FUNCTION public.get_public_club_by_id(text) TO anon, authenticated;;
