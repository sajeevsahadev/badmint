-- AI Video Coaching: move video bytes to Cloudflare R2 only.
-- Removes the Supabase Storage object policies created in v100_match_videos.sql.
-- The public.match_videos METADATA table and its RLS are kept as-is (still in Supabase);
-- only the stored video objects move to R2 (presigned via the video-sign Edge Function).
-- Applied to project bdmiirppiyopmdfrztoz via MCP.
--
-- NOTE: the 'match-videos' bucket itself cannot be dropped from SQL — Supabase guards
-- storage.objects/buckets with a protect_delete trigger. Delete the (now unused, empty)
-- bucket from the dashboard: Storage → match-videos → Delete bucket.

drop policy if exists mvobj_select on storage.objects;
drop policy if exists mvobj_insert on storage.objects;
drop policy if exists mvobj_delete on storage.objects;
