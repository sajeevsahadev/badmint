# Auto‑rebuild so scheduled posts get their SEO HTML

Scheduled posts appear in the app instantly (the database reveals them at `publish_at`).
But the **static SEO HTML + sitemap** that Google and social scrapers read are generated
at *build time* — so we ping a rebuild twice a week, right after the Tue/Fri 09:00 UTC
publish slots. The rebuild writes zero content (posts are already written), so it can't
break anything.

## Step 1 — Create a Vercel Deploy Hook (one‑time, ~1 min)
1. Vercel → your Badminton 360 project → **Settings → Git → Deploy Hooks**
2. Create hook: **Name** `blog-refresh`, **Branch** `main` → **Create Hook**
3. Copy the URL (looks like `https://api.vercel.com/v1/integrations/deploy/prj_xxx/yyy`)

⚠️ Treat this URL as semi‑secret (anyone with it can trigger a build). Don't post it in chat.

## Step 2 — Schedule the twice‑weekly rebuild (Supabase pg_cron)
You already have `pg_cron` + `pg_net` enabled (the weekly digest uses them). In the
**Supabase SQL editor**, run this — replacing `DEPLOY_HOOK_URL` with your hook:

```sql
select cron.schedule(
  'blog-rebuild',
  '5 9 * * 2,5',                       -- 09:05 UTC every Tuesday & Friday
  $$ select net.http_post(url := 'DEPLOY_HOOK_URL') $$
);
```

That's it. Every Tue & Fri at 09:05 UTC, Vercel rebuilds; any post whose `publish_at`
has passed becomes live with full prerendered SEO HTML and an updated sitemap.

To change later:
```sql
select cron.unschedule('blog-rebuild');   -- remove
-- then re-run cron.schedule with a new time/URL
```

## Notes
- The 09:05 time is 5 minutes after the 09:00 publish slots, so the post is already
  live in the DB when the rebuild runs.
- Prefer not to run SQL yourself? Paste me the hook URL and I'll schedule it via the
  Supabase tools — but the SQL above keeps the hook entirely on your side.
- Nothing breaks if a rebuild is skipped: the post is still visible in the app; only its
  prerendered HTML waits for the next build.
