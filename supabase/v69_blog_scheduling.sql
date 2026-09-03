-- v69_blog_scheduling
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

ALTER TABLE blog_posts ADD COLUMN IF NOT EXISTS publish_at timestamptz;
UPDATE blog_posts SET publish_at = created_at WHERE publish_at IS NULL;
ALTER TABLE blog_posts ALTER COLUMN publish_at SET DEFAULT now();
ALTER TABLE blog_posts ALTER COLUMN publish_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_blog_publish_at ON blog_posts(publish_at DESC) WHERE published;

-- Public sees only posts that are published AND whose scheduled time has arrived.
-- Admins see everything (drafts + scheduled future posts).
DROP POLICY IF EXISTS bp_read ON blog_posts;
CREATE POLICY bp_read ON blog_posts FOR SELECT
  USING ((published = true AND publish_at <= now()) OR is_app_admin());;
