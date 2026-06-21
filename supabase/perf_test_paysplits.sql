-- =====================================================================
-- Badminton 360 — PaySplits Performance Benchmark Queries
--
-- Run AFTER load_test_paysplits.sql has been executed.
-- Replace TEST_CLUB_ID with the club_id printed by that script, or run:
--   SELECT id FROM clubs ORDER BY created_at LIMIT 1;
--
-- Each query uses EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) to capture:
--   - Actual execution time
--   - Buffer hits vs disk reads
--   - Rows processed at each node
--
-- Expected targets (Supabase free-tier, 10,000 expenses + 5,000 contribs):
--   get_expenses        < 500ms   (heavy jsonb_agg + 4 joins)
--   get_balance_summary < 300ms   (CTE-based netted pairs)
--   get_wallet_data     < 400ms   (3 sub-aggregations in one jsonb)
--   get_opening_balances < 50ms   (small table, indexed UNIQUE)
-- =====================================================================

-- ── 0. Find your test club ID ─────────────────────────────────────────
-- Run this first if you don't have it:
-- SELECT id, name FROM clubs ORDER BY created_at LIMIT 1;

-- Replace this value throughout the file:
\set TEST_CLUB_ID 'PASTE-YOUR-CLUB-ID-HERE'

-- ── 1. get_expenses performance ───────────────────────────────────────
-- This is the heaviest query: jsonb_agg over participants with 4 JOINs,
-- scanned across up to 10,000 expense rows for a single club.
--
-- Expected plan: Index Scan on idx_paysplit_expenses_club → Hash Join on
-- participants → Hash Join on players/user_profiles.
-- Without idx_paysplit_expenses_club: Seq Scan (fatal at scale).
-- Without idx_paysplit_participants_expense_id: Nested Loop (O(n*m)).

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM get_expenses(:'TEST_CLUB_ID'::uuid);

-- ── 2. get_balance_summary performance ────────────────────────────────
-- Aggregates ALL non-wallet expense participants pairwise.
-- At 10,000 expenses × avg 10 participants = 100,000 participant rows.
-- CTE approach: raw → netted → resolved names.
--
-- Expected plan: Hash Aggregate on (LEAST/GREATEST pair) → Hash Join
-- players + user_profiles. Should stay < 300ms with proper indexes.

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM get_balance_summary(:'TEST_CLUB_ID'::uuid);

-- ── 3. get_wallet_data performance ────────────────────────────────────
-- Returns 3 sub-aggregations in a single jsonb object:
--   contributions (FIFO-ordered)
--   wallet_expenses
--   player_balances (contributed vs expense share)
-- All are sequential scans of club-filtered data.
--
-- At 5,000 wallet contributions the jsonb_agg in the contributions
-- sub-query may materialise a large intermediate result. Watch for
-- Sort nodes (ORDER BY contributed_at) and whether they spill to disk.

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM get_wallet_data(:'TEST_CLUB_ID'::uuid);

-- ── 4. get_opening_balances performance ───────────────────────────────
-- Simple lookup on paysplit_opening_balances (club_id, player_id UNIQUE).
-- 50 rows max — should always be < 10ms.

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM get_opening_balances(:'TEST_CLUB_ID'::uuid);

-- ── 5. Raw table row counts (baseline reference) ──────────────────────
SELECT
  (SELECT COUNT(*) FROM paysplit_expenses        WHERE club_id = :'TEST_CLUB_ID'::uuid) AS expenses,
  (SELECT COUNT(*) FROM paysplit_participants pp
     JOIN paysplit_expenses e ON e.id = pp.expense_id
     WHERE e.club_id = :'TEST_CLUB_ID'::uuid)                                            AS participants,
  (SELECT COUNT(*) FROM wallet_contributions     WHERE club_id = :'TEST_CLUB_ID'::uuid) AS wallet_contribs,
  (SELECT COUNT(*) FROM paysplit_opening_balances WHERE club_id = :'TEST_CLUB_ID'::uuid) AS opening_bals;

-- ── 6. Verify indexes exist ───────────────────────────────────────────
SELECT
  indexname,
  tablename,
  indexdef
FROM pg_indexes
WHERE tablename IN (
  'paysplit_expenses',
  'paysplit_participants',
  'wallet_contributions',
  'paysplit_opening_balances'
)
ORDER BY tablename, indexname;

-- ── 7. Simulate the frontend FIFO loop in SQL (sanity check) ──────────
-- This materialises the same data that fifoResult computed() loads into
-- the browser. Count the rows to understand what JavaScript iterates over.
WITH contrib_count AS (
  SELECT COUNT(*) AS n FROM wallet_contributions WHERE club_id = :'TEST_CLUB_ID'::uuid
),
wallet_exp_count AS (
  SELECT COUNT(*) AS m FROM paysplit_expenses
  WHERE club_id = :'TEST_CLUB_ID'::uuid AND paid_from_wallet = true
)
SELECT
  c.n                    AS contributions,
  w.m                    AS wallet_expenses,
  c.n * w.m              AS fifo_iterations_worst_case,
  CASE
    WHEN c.n * w.m > 10000000 THEN 'CRITICAL: >10M iterations — will freeze browser'
    WHEN c.n * w.m > 1000000  THEN 'HIGH: >1M iterations — noticeable lag (>1s)'
    WHEN c.n * w.m > 100000   THEN 'MEDIUM: >100K iterations — mild lag on slow devices'
    ELSE 'OK: manageable in browser'
  END AS risk_level
FROM contrib_count c, wallet_exp_count w;
