-- =====================================================================
-- Badminton 360 v36b — PaySplits: server-side FIFO + missing index fix
-- Run in Supabase SQL Editor (after v35_schema.sql or v36_schema.sql)
--
-- Problem: The frontend fifoResult computed in PaySplits.vue runs an
-- O(contributions × wallet_expenses) nested loop in the browser.
-- At 5,000 contributions × 2,000 wallet expenses = 10M iterations,
-- causing UI freezes on real devices.
--
-- Fix 1: Add missing paysplit_participants(expense_id) index that
--         get_expenses needs (v27 only added player_id index).
--
-- Fix 2: get_fifo_result() SECURITY DEFINER RPC computes the FIFO
--         wallet allocation entirely in SQL using window functions
--         (set-based, O(C + W)), returning the same shape the frontend
--         currently builds in the browser.
-- =====================================================================

-- ── Fix 1: Missing index ─────────────────────────────────────────────
-- v27 added idx_paysplit_participants_player (player_id column) but
-- get_expenses does: LEFT JOIN paysplit_participants pa ON pa.expense_id = e.id
-- This join uses expense_id — a missing index causes a Seq Scan over the
-- full participants table for every expense row at query time.
CREATE INDEX IF NOT EXISTS idx_paysplit_participants_expense_id
  ON paysplit_participants(expense_id);

-- Also useful for ON DELETE CASCADE from paysplit_expenses (Postgres
-- checks this FK on every expense delete without an index).
-- (No-op if already exists from a future migration.)

-- ── Fix 2: get_fifo_result RPC ───────────────────────────────────────
-- Returns the same shape as the browser's fifoResult computed:
--
--   active:   contributions with remaining > 0
--   consumed: contributions fully depleted (with consumedBy details)
--
-- Each contribution row includes:
--   id, player_id, player_name, amount, notes, contributed_at,
--   created_by, remaining, consumed_by (jsonb array)
--
-- Algorithm (set-based, no nested loop):
--   1. Number contributions in FIFO order (contributed_at ASC).
--   2. Compute cumulative contribution total up to (and including) each
--      contribution (running_through) and up to (not including) each
--      contribution (running_before).
--   3. Number wallet expenses in chronological order and compute their
--      cumulative totals the same way.
--   4. A contribution C covers expense E when their cumulative ranges
--      overlap:
--        running_before_C < running_through_E   (C starts before E ends)
--        AND running_through_C > running_before_E (C ends after E starts)
--      The actual amount taken from C toward E is:
--        LEAST(running_through_C, running_through_E)
--        - GREATEST(running_before_C, running_before_E)
--   5. Aggregate consumedBy per contribution, compute remaining.
--
-- Complexity: O(C + W) for the window functions + O(overlap_count) for
-- the range join. In practice overlap_count ≈ C × avg_expenses_per_contrib
-- which is much smaller than C × W because early contributions are fully
-- consumed by a handful of expenses.
-- =====================================================================

DROP FUNCTION IF EXISTS get_fifo_result(uuid);

CREATE OR REPLACE FUNCTION get_fifo_result(p_club_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Auth check: caller must be a club member
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid()
  ) THEN
    RETURN NULL;
  END IF;

  WITH
  -- ── Contributions with cumulative prefix sums ──────────────────────
  contribs_raw AS (
    SELECT
      wc.id,
      wc.player_id,
      COALESCE(up.nickname, p.display_name) AS player_name,
      wc.amount::numeric                     AS amount,
      wc.notes,
      wc.contributed_at,
      wc.created_by,
      -- Cumulative total BEFORE this contribution (exclusive)
      COALESCE(
        SUM(wc.amount::numeric) OVER (
          ORDER BY wc.contributed_at, wc.id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), 0
      ) AS running_before,
      -- Cumulative total THROUGH this contribution (inclusive)
      SUM(wc.amount::numeric) OVER (
        ORDER BY wc.contributed_at, wc.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS running_through
    FROM wallet_contributions wc
    JOIN players p ON p.id = wc.player_id
    LEFT JOIN user_profiles up ON up.user_id = p.user_id
    WHERE wc.club_id = p_club_id
  ),

  -- ── Wallet-paid expenses with cumulative prefix sums ──────────────
  expenses_raw AS (
    SELECT
      e.id,
      e.title,
      e.amount::numeric AS amount,
      e.expense_date,
      -- Cumulative expense total BEFORE this expense (exclusive)
      COALESCE(
        SUM(e.amount::numeric) OVER (
          ORDER BY e.expense_date, e.created_at, e.id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), 0
      ) AS running_before,
      -- Cumulative expense total THROUGH this expense (inclusive)
      SUM(e.amount::numeric) OVER (
        ORDER BY e.expense_date, e.created_at, e.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS running_through
    FROM paysplit_expenses e
    WHERE e.club_id = p_club_id
      AND e.paid_from_wallet = true
  ),

  -- ── Range overlap join: which contribution covers which expense ────
  -- A contribution C covers expense E when their cumulative ranges overlap.
  -- The taken amount is the intersection length of the two ranges.
  allocations AS (
    SELECT
      c.id           AS contrib_id,
      e.id           AS expense_id,
      e.title        AS expense_title,
      e.expense_date,
      -- Amount taken from this contribution toward this expense
      LEAST(c.running_through, e.running_through)
        - GREATEST(c.running_before, e.running_before) AS taken
    FROM contribs_raw c
    JOIN expenses_raw e
      ON c.running_before < e.running_through   -- C starts before E ends
     AND c.running_through > e.running_before   -- C ends after E starts
    WHERE
      -- Positive intersection only (floating point safety)
      LEAST(c.running_through, e.running_through)
        - GREATEST(c.running_before, e.running_before) > 0.004
  ),

  -- ── Per-contribution: aggregate consumedBy + compute remaining ────
  contrib_summary AS (
    SELECT
      c.id,
      c.player_id,
      c.player_name,
      c.amount,
      c.notes,
      c.contributed_at,
      c.created_by,
      -- Remaining balance (amount minus all taken amounts)
      GREATEST(
        0,
        c.amount - COALESCE(SUM(a.taken), 0)
      ) AS remaining,
      -- ConsumedBy array (matches frontend shape)
      COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'expenseId',    a.expense_id,
            'title',        a.expense_title,
            'amount',       ROUND(a.taken::numeric, 2),
            'expense_date', a.expense_date
          )
          ORDER BY a.expense_date
        ) FILTER (WHERE a.expense_id IS NOT NULL),
        '[]'::jsonb
      ) AS consumed_by
    FROM contribs_raw c
    LEFT JOIN allocations a ON a.contrib_id = c.id
    GROUP BY c.id, c.player_id, c.player_name, c.amount,
             c.notes, c.contributed_at, c.created_by
  )

  -- ── Build the final jsonb matching frontend fifoResult shape ───────
  SELECT jsonb_build_object(
    'active',
    COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'id',           cs.id,
          'player_id',    cs.player_id,
          'player_name',  cs.player_name,
          'amount',       cs.amount,
          'notes',        cs.notes,
          'contributed_at', cs.contributed_at,
          'created_by',   cs.created_by,
          'remaining',    ROUND(cs.remaining, 2),
          'consumedBy',   cs.consumed_by
        ) ORDER BY cs.contributed_at
      ) FROM contrib_summary cs WHERE cs.remaining > 0.005),
      '[]'::jsonb
    ),
    'consumed',
    COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'id',           cs.id,
          'player_id',    cs.player_id,
          'player_name',  cs.player_name,
          'amount',       cs.amount,
          'notes',        cs.notes,
          'contributed_at', cs.contributed_at,
          'created_by',   cs.created_by,
          'remaining',    ROUND(cs.remaining, 2),
          'consumedBy',   cs.consumed_by
        ) ORDER BY cs.contributed_at
      ) FROM contrib_summary cs
        WHERE cs.remaining <= 0.005
          AND jsonb_array_length(cs.consumed_by) > 0),
      '[]'::jsonb
    )
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_fifo_result(uuid) TO authenticated;

-- ── Usage note ────────────────────────────────────────────────────────
-- In PaySplits.vue, replace the fifoResult computed with:
--
--   const fifoResult = ref({ active: [], consumed: [] })
--
--   async function loadFifoResult() {
--     const { data } = await supabase.rpc('get_fifo_result', {
--       p_club_id: currentClub.value.club_id
--     })
--     fifoResult.value = data ?? { active: [], consumed: [] }
--   }
--
-- Call loadFifoResult() alongside loadWalletData() in loadAllData().
-- The walletExpenseContributors computed can then invert fifoResult.value
-- from the server-returned data instead of re-computing in the browser.
--
-- walletData.value is still needed for the Wallet tab's contribution list
-- UI and the player_balances display — only the FIFO allocation moves to SQL.
