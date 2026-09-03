-- v68_blog_posts
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

CREATE TABLE IF NOT EXISTS blog_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text UNIQUE NOT NULL,
  title text NOT NULL,
  excerpt text,
  cover_url text,
  body text NOT NULL,                 -- HTML
  meta_description text,
  keywords text,
  author text NOT NULL DEFAULT 'Badminton 360',
  published boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_blog_published ON blog_posts(published, created_at DESC);

ALTER TABLE blog_posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bp_read ON blog_posts;
CREATE POLICY bp_read ON blog_posts FOR SELECT
  USING (published = true OR is_app_admin());

DROP POLICY IF EXISTS bp_write ON blog_posts;
CREATE POLICY bp_write ON blog_posts FOR ALL
  USING (is_app_admin()) WITH CHECK (is_app_admin());

-- Public (anon) can read published posts for SEO; admins write.
GRANT SELECT ON blog_posts TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON blog_posts TO authenticated;

-- keep updated_at fresh
CREATE OR REPLACE FUNCTION blog_touch_updated() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS trg_blog_touch ON blog_posts;
CREATE TRIGGER trg_blog_touch BEFORE UPDATE ON blog_posts
  FOR EACH ROW EXECUTE FUNCTION blog_touch_updated();;
