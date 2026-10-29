# Weekly Slow-Query Review

Badminton 360 is built for global scale (millions of rows per table eventually). Initial
loads can feel slow intermittently. This is the weekly routine to catch slow queries
**before** they become user-visible at scale.

## How logging works (automatic — v139)

- Postgres `pg_stat_statements` aggregates every query's live timing (already enabled).
- `snapshot_slow_queries()` captures the top offenders (mean ≥ 40ms, ≥ 5 calls) into
  `public.perf_slow_query_log` with `mean_ms / max_ms / total_ms / calls / rows`.
- **pg_cron job `weekly-slow-query-snapshot` runs it every Sunday 03:00 UTC.** Snapshots
  older than 180 days are auto-pruned. Only normalised query text ($1 placeholders) is
  stored — no literal values leak in. The table is RLS-locked; read only via the
  `admin_get_slow_queries()` RPC (app_admin).

## The weekly task (do this once a week)

1. Pull the last ~2 weeks of snapshots:
   ```sql
   SELECT captured_at::date, round(mean_ms,1) mean_ms, round(max_ms,1) max_ms,
          calls, left(query,160) q
   FROM admin_get_slow_queries('14 days', 200)
   ORDER BY mean_ms DESC LIMIT 40;
   ```
   (Or, as the DB owner via MCP, read `perf_slow_query_log` directly.)
2. Ignore infra noise: `net.http_post` (email/push cron fan-out), `auth.users`,
   `storage.objects`, `realtime.*`, `pg_catalog`/`information_schema`. Focus on our own
   `public.*` RPCs and views (leaderboard, clubs, matches, balance summary, FIFO, etc.).
3. For each real offender, get the plan on representative data:
   ```sql
   EXPLAIN (ANALYZE, BUFFERS) <the query with real params>;
   ```
   Look for `Seq Scan` on big tables, sorts spilling to disk, nested loops over large sets.
4. Fix by **migration** (never hand-ALTER): add the missing composite index, narrow a
   `SELECT *`, add pagination/`LIMIT`, or push work into a SECURITY DEFINER RPC. Add the
   index `CONCURRENTLY` in its own migration if the table is already large.
5. Re-measure the same query after the change; record the before/after in the commit.

## Rules

- **Don't add speculative indexes on a near-empty dev DB** — you'll guess wrong. Act on
  real captured timings and real `EXPLAIN` output.
- One index per real, measured offender. Every index slows writes, so justify each.
- Schema changes go through a numbered migration (`supabase/vNNN_schema.sql`) applied via
  MCP, same as everything else.

## Manual snapshot (outside the weekly cron)

```sql
SELECT snapshot_slow_queries();          -- defaults: mean ≥ 40ms, ≥ 5 calls, top 50
SELECT snapshot_slow_queries(20, 3, 60); -- more sensitive capture
```
