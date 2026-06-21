# PaySplits Performance Analysis

## 1. Frontend FIFO Loop — O(n²) Finding

**File:** `src/views/PaySplits.vue`, `fifoResult` computed (lines 313–348)

### The loop structure

```js
const fifoResult = computed(() => {
  const contribs = [...walletData.value.contributions]   // C rows, sorted
  const wExps    = [...walletData.value.wallet_expenses] // W rows, sorted

  wExps.forEach(exp => {            // outer: W iterations
    let toConsume = Number(exp.amount)
    for (const c of contribs) {    // inner: C iterations each time
      if (remaining[c.id] < 0.005 || toConsume < 0.005) continue
      const take = Math.min(remaining[c.id], toConsume)
      ...
    }
  })
})
```

### Complexity

This is **O(C × W)** where:
- C = number of wallet contributions for the club
- W = number of wallet-paid expenses for the club

The inner loop iterates over **all** contributions for every expense — there is no early-exit once all contributions up to the current expense date are consumed. The `continue` skips individual depleted contributions but still walks the whole array.

### Iteration counts at load-test scale

| Scenario | Contributions (C) | Wallet Expenses (W) | Iterations |
|---|---|---|---|
| Small club (real-world typical) | 50 | 100 | 5,000 — fine |
| Medium club (1 year active) | 500 | 500 | 250,000 — noticeable lag |
| Load-test scale | 5,000 | 2,000 (20% of 10K) | **10,000,000** — browser freeze |
| Worst case | 10,000 | 5,000 | **50,000,000** — complete UI lockup |

At 5,000 contributions × 2,000 wallet expenses = **10 million iterations** running synchronously in the Vue computed getter. On a mid-range phone this will freeze the UI for several seconds or cause the browser to display a "page not responding" prompt.

### Why the early-exit doesn't help

The `continue` on `remaining[c.id] < 0.005` only skips writing, not iterating. The inner `for` loop always scans the full contribution array for every expense. A truly depleted contribution at position 0 is still visited for every single one of the W expense rows.

### Additional issue: walletExpenseContributors secondary computed

```js
const walletExpenseContributors = computed(() => {
  const allContribs = [...fifoResult.value.active, ...fifoResult.value.consumed]
  allContribs.forEach(c => {
    c.consumedBy.forEach(cb => { ... })  // O(C × W) again, building the inverse map
  })
})
```

This adds a second O(C × W) pass over the same data. Total browser-side work is roughly **2 × C × W**.

---

## 2. Server-side Query Analysis

### get_expenses

**Complexity:** O(E + P) where E = expenses, P = participants
**Bottleneck:** `jsonb_agg` over participants requires materialising all participant rows per expense. With 10,000 expenses × avg 10 participants = 100,000 participant rows aggregated into JSON.

The `GROUP BY` + `jsonb_agg` on 100K rows is the dominant cost. The `idx_paysplit_expenses_club` index (added in v27) enables an index scan for the base filter; `idx_paysplit_participants_player` helps the participant join but an index on `expense_id` would be better for this access pattern.

**Missing index identified:**
```sql
-- NOT in v27: paysplit_participants(expense_id) for the jsonb_agg join
-- v27 only has idx_paysplit_participants_player ON paysplit_participants(player_id)
-- The get_expenses join is: LEFT JOIN paysplit_participants pa ON pa.expense_id = e.id
-- This needs an index on expense_id, not player_id
CREATE INDEX IF NOT EXISTS idx_paysplit_participants_expense_id
  ON paysplit_participants(expense_id);
```

### get_balance_summary

**Complexity:** O(P log P) for the hash aggregate
**Risk:** At 100K participant rows (non-wallet), the CTE materialises the full `raw` set then hashes pairs. PostgreSQL will handle this in memory unless work_mem is very low. Should be fine for Supabase free tier.

### get_wallet_data

**Complexity:** Three independent aggregations, each O(C) or O(P_wallet)
**Risk:** The `jsonb_agg(...ORDER BY contributed_at)` over 5,000 contribution rows builds a large JSON array in memory. This is a single large allocation but not algorithmically expensive.

**Real risk:** the returned JSON blob is deserialized in the browser as `walletData.value`, then the `fifoResult` computed iterates it in O(C × W). The server-side cost is acceptable; the browser-side cost is not.

### get_opening_balances

**Complexity:** O(50) — trivially small, always fast.

---

## 3. Index Gaps

After reviewing v27_schema.sql (the performance indexes migration), these are the findings:

| Index | Present in v27? | Notes |
|---|---|---|
| `paysplit_expenses(club_id, expense_date DESC)` | YES — `idx_paysplit_expenses_club` | Correct |
| `paysplit_participants(player_id)` | YES — `idx_paysplit_participants_player` | Wrong column for `get_expenses` join |
| `paysplit_participants(expense_id)` | **MISSING** | Needed for `get_expenses` LEFT JOIN |
| `wallet_contributions(club_id, contributed_at)` | YES — `idx_wallet_contributions_club` | Correct |
| `paysplit_expense_payers(expense_id)` | N/A — table doesn't exist yet | Only needed if v36 multi-payer lands |

---

## 4. Fix: Move FIFO to SQL (v36b_schema.sql)

The solution is a `get_fifo_result` SECURITY DEFINER RPC that computes the FIFO allocation entirely in SQL using window functions and cumulative sums — no nested loop required. See `v36b_schema.sql`.

**SQL approach (set-based, O(C + W) with window functions):**
1. Assign each contribution a cumulative `running_total` (prefix sum, ordered by `contributed_at`)
2. Assign each wallet expense a cumulative `running_expense` (prefix sum, ordered by date/created_at)
3. A contribution C_i is consumed by expense E_j when:
   `running_expense_before_j < running_contrib_through_i`
   and `running_expense_through_j > running_contrib_before_i`
4. This is a range overlap join — can be expressed as a CTE with window functions.

The frontend then replaces `fifoResult` computed with a single `get_fifo_result(clubId)` RPC call and renders the returned data directly, eliminating the O(n²) loop entirely.

---

## 5. Summary — Action Priority

| Priority | Issue | Fix |
|---|---|---|
| **P0 — Critical** | `fifoResult` O(C × W) loop freezes browser at scale | Replace with `get_fifo_result` SQL RPC (v36b) |
| **P1 — High** | Missing `paysplit_participants(expense_id)` index | Add in v36b_schema.sql |
| **P2 — Medium** | `get_expenses` returns all 10K rows to browser | Add pagination param `p_limit / p_offset` |
| **P3 — Low** | `walletExpenseContributors` double-iterates FIFO result | Resolved by P0 fix |
