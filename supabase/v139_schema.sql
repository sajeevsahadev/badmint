-- =====================================================================
-- Badminton 360 v139 — Slow-query logging + weekly snapshot
-- Applied to prod via Supabase MCP; archived for rebuild parity.
--
-- Built for scale (millions of rows per table): pg_stat_statements aggregates live
-- query timings but keeps no history, so this snapshots the top offenders weekly into
-- a durable table to make trends visible over time. See docs/perf-weekly-review.md.
--
--   * perf_slow_query_log       — captured snapshots (RLS-locked; read via RPC only).
--   * snapshot_slow_queries()   — inserts top offenders from pg_stat_statements
--       (mean >= p_min_mean_ms, >= p_min_calls); normalised query text only ($1
--       placeholders), no literals; prunes rows older than 180 days. Run by pg_cron.
--   * admin_get_slow_queries()  — app_admin reader for the weekly review / any Admin UI.
--   * pg_cron 'weekly-slow-query-snapshot' — Sundays 03:00 UTC.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.perf_slow_query_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  captured_at timestamptz NOT NULL DEFAULT now(),
  queryid     bigint,
  query       text,
  calls       bigint,
  mean_ms     numeric,
  max_ms      numeric,
  total_ms    numeric,
  rows        bigint
);
CREATE INDEX IF NOT EXISTS idx_perf_slow_captured ON public.perf_slow_query_log (captured_at DESC);
ALTER TABLE public.perf_slow_query_log ENABLE ROW LEVEL SECURITY;  -- no policies: definer RPCs only

CREATE OR REPLACE FUNCTION public.snapshot_slow_queries(
  p_min_mean_ms numeric DEFAULT 40,
  p_min_calls   bigint  DEFAULT 5,
  p_limit       int     DEFAULT 50
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE n int;
BEGIN
  INSERT INTO public.perf_slow_query_log (queryid, query, calls, mean_ms, max_ms, total_ms, rows)
  SELECT s.queryid, left(s.query, 2000), s.calls,
         round(s.mean_exec_time::numeric, 2),
         round(s.max_exec_time::numeric, 2),
         round(s.total_exec_time::numeric, 2),
         s.rows
  FROM extensions.pg_stat_statements s
  WHERE s.mean_exec_time >= p_min_mean_ms
    AND s.calls >= p_min_calls
    AND s.query !~* '(pg_stat_statements|perf_slow_query_log|snapshot_slow_queries|^\s*(COMMIT|BEGIN|ROLLBACK|SET|SHOW)\b|cron\.)'
  ORDER BY s.mean_exec_time DESC
  LIMIT p_limit;
  GET DIAGNOSTICS n = ROW_COUNT;
  DELETE FROM public.perf_slow_query_log WHERE captured_at < now() - interval '180 days';
  RETURN n;
END;
$function$;
REVOKE ALL ON FUNCTION public.snapshot_slow_queries(numeric, bigint, int) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_get_slow_queries(
  p_since interval DEFAULT '30 days',
  p_limit int      DEFAULT 200
) RETURNS SETOF public.perf_slow_query_log LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  RETURN QUERY
    SELECT * FROM public.perf_slow_query_log
    WHERE captured_at >= now() - p_since
    ORDER BY captured_at DESC, mean_ms DESC
    LIMIT p_limit;
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_get_slow_queries(interval, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_slow_queries(interval, int) TO authenticated;

SELECT cron.schedule('weekly-slow-query-snapshot', '0 3 * * 0',
  $$SELECT public.snapshot_slow_queries();$$);
