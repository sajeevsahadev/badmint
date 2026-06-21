# PaySplits Feature — Comprehensive Test Cases

**Scope:** PaySplits module in Badminton 360 (`src/views/PaySplits.vue`).
Covers existing functionality (v11/v12/v19 schema) plus the new multi-payer feature (v36 schema: `paysplit_expense_payers` table, updated `add_expense`/`update_expense`/`get_balance_summary` RPCs).

**Last updated:** 2026-06-21
**Tester role assumed:** club member unless stated otherwise.

---

## TC023 — Multi-Payer Math Trace (get_balance_summary)

**Scenario:** AED 100 expense. A pays 60, B pays 40. Four participants: A, B, C, D (equal split).

**Step 1 — share per participant**
```
share = 100 / 4 = 25.00 AED each
```

**Step 2 — raw_debts from multi-payer branch (v36 SQL)**

Each participant owes each payer: `ROUND(pp.share × pep.amount / e.amount, 4)`

| Participant (from_id) | Payer (to_id) | Calculation        | Amount  |
|-----------------------|---------------|--------------------|---------|
| C                     | A             | 25 × 60/100        | 15.0000 |
| C                     | B             | 25 × 40/100        | 10.0000 |
| D                     | A             | 25 × 60/100        | 15.0000 |
| D                     | B             | 25 × 40/100        | 10.0000 |
| A (participant)       | B (payer)     | 25 × 40/100        | 10.0000 |
| B (participant)       | A (payer)     | 25 × 60/100        | 15.0000 |

*(Row is excluded where `pp.player_id = pep.player_id` — a payer never owes themselves.)*

**Step 3 — paired netting**

LEAST/GREATEST pairing collapses A↔B bidirectional debts:
- A↔B pair: B owes A 15, A owes B 10 → net = 15 − 10 = **+5** (A is net getter, B is net ower)

Final `get_balance_summary` output rows:

| from_name | to_name | net_amount |
|-----------|---------|------------|
| B         | A       | 5.00       |
| C         | A       | 15.00      |
| C         | B       | 10.00      |
| D         | A       | 15.00      |
| D         | B       | 10.00      |

**Step 4 — per-player net position check**
- A: gets 5 (from B) + 15 (from C) + 15 (from D) = **+35** ✓ (paid 60, share 25 → gets back 35)
- B: gets 10 (from C) + 10 (from D) − 5 (owes A) = **+15** ✓ (paid 40, share 25 → gets back 15)
- C: owes 15 + 10 = **−25** ✓
- D: owes 15 + 10 = **−25** ✓

Total nets sum to zero: 35 + 15 − 25 − 25 = 0 ✓

---

## Section 1 — Add Expense: Single Payer

### TC001
**Priority:** P0 | **Status:** Manual

**Given** I am a club member on the PaySplits Activities tab with 4 active players.

**When** I tap "Add Expense", fill in title "Court Rent", category "facility", amount 100, payer = PlayerA, date = today, select all 4 participants, and tap Save.

**Then** the expense appears in the Activities list with "Court Rent · AED 100.00 · paid by PlayerA, 4 people". The Balance tab reflects each non-payer owing PlayerA AED 25.00 (100 / 4 = 25).

---

### TC002
**Priority:** P0 | **Status:** Manual

**Given** I am a club member on the Add Expense form.

**When** I enter only title "Water", amount 20, payer = myself, leave all other participants defaulted (all active players), and tap Save.

**Then** the expense saves successfully. The category defaults to "other".

---

### TC003
**Priority:** P0 | **Status:** Can be automated (form validation unit test)

**Given** I am on the Add Expense form.

**When** I leave the title blank, fill in amount 50, select a payer and participants, and tap Save.

**Then** an inline error "Title is required" is shown. The form does not close and no RPC is called.

---

### TC004
**Priority:** P0 | **Status:** Can be automated

**Given** I am on the Add Expense form.

**When** I enter title "Test", set amount to 0 (or leave blank), and tap Save.

**Then** an inline error "Enter a valid amount" is shown. The form does not close.

---

### TC005
**Priority:** P0 | **Status:** Can be automated

**Given** I am on the Add Expense form with all participants deselected.

**When** I fill in title "Test", amount 50, payer = myself, and tap Save.

**Then** an inline error "Select at least one participant" is shown. The form does not close.

---

### TC006
**Priority:** P1 | **Status:** Manual

**Given** I am on the Add Expense form with title field empty.

**When** I tap the "Court Rent" category chip.

**Then** the category selector highlights "facility" and the title field auto-fills with "Court Rent". If I then tap a different category with the title still matching the auto-fill value, the title updates to the new category label.

---

### TC007
**Priority:** P1 | **Status:** Manual

**Given** A schedule entry for today exists for the club with 3 confirmed attendees (P1, P2, P3) out of 4 active players.

**When** I open Add Expense and leave the date as today.

**Then** the participant list auto-filters to show only P1, P2, P3 pre-ticked. A "Show all players" toggle appears. Tapping it reveals all 4 active players.

---

### TC008
**Priority:** P1 | **Status:** Manual

**Given** The club wallet has AED 30.00 balance. I am on the Add Expense form.

**When** I select "Pay from Wallet" as payment source and enter amount 50, then tap Save.

**Then** an error "Wallet balance is AED 30.00 — not enough to cover this expense." is shown. The expense is not saved.

---

## Section 2 — Add Expense: Multi-Payer (v36)

### TC009
**Priority:** P0 | **Status:** Manual

**Given** I am on the Add Expense form with "Multi-payer" toggled on. Players: A, B, C, D (all active).

**When** I enter title "Court Rent", amount 100, payers: A = 60 / B = 40, all 4 participants, and tap Save.

**Then** the expense saves successfully. The Activities list shows "paid by A, B (multi)" or equivalent multi-payer indicator. No validation error is shown.

---

### TC010
**Priority:** P0 | **Status:** Manual

**Given** A saved multi-payer expense: AED 100, payers A=60/B=40, participants A/B/C/D.

**When** I open the Balance tab.

**Then** the debt rows match the expected output from TC023:
- B owes A: AED 5.00
- C owes A: AED 15.00
- C owes B: AED 10.00
- D owes A: AED 15.00
- D owes B: AED 10.00

No extra rows. All player nets sum to zero.

---

### TC011
**Priority:** P0 | **Status:** Can be automated (form validation)

**Given** I am on the Add Expense form with multi-payer mode on, total amount = 100.

**When** I enter payer A = 60, payer B = 30 (sum = 90, not 100), and tap Save.

**Then** an inline validation error is shown indicating the payer amounts do not sum to the total (e.g. "Payer amounts must sum to AED 100.00"). The expense is not saved.

---

### TC012
**Priority:** P1 | **Status:** Manual

**Given** I am on the Add Expense form in single-payer mode with payer set to PlayerA.

**When** I toggle "Multi-payer" on.

**Then** the single-payer selector is replaced by the multi-payer payer-amount rows. The form shows empty payer rows (no prior payer pre-filled or pre-populated in the multi-payer list from the single-payer selection).

---

### TC013
**Priority:** P1 | **Status:** Manual

**Given** I am on the Add Expense form in multi-payer mode with A=60, B=40 entered.

**When** I toggle "Multi-payer" off.

**Then** the multi-payer rows disappear. The single-payer selector is shown. Previously entered multi-payer amounts are cleared. The payer field defaults back to the current player or blank.

---

### TC014
**Priority:** P1 | **Status:** Manual

**Given** I am on the Add Expense form with multi-payer mode on and only one payer amount entered (A = 100).

**When** I tap Save with valid title, amount, participants.

**Then** the expense is saved as a single-payer expense (the v36 RPC treats `jsonb_array_length(p_payers) = 1` as single-payer: sets `paid_player_id` to that one player, does not insert into `paysplit_expense_payers`). No multi-payer debt edges are generated.

---

## Section 3 — Edit Expense

### TC015
**Priority:** P0 | **Status:** Manual

**Given** An existing single-payer expense: "Water" AED 20, paid by PlayerA, participants A+B.

**When** I tap the expense to expand it, tap Edit.

**Then** the form opens pre-populated: title = "Water", amount = "20", payer = PlayerA, participants = [A, B], multi-payer toggle = off.

---

### TC016
**Priority:** P0 | **Status:** Manual

**Given** An existing multi-payer expense: AED 100, payers A=60/B=40, participants A/B/C/D.

**When** I tap Edit on that expense.

**Then** the form opens with multi-payer toggle on. Payer rows show A=60 and B=40 pre-filled. Participants A/B/C/D are checked.

---

### TC017
**Priority:** P1 | **Status:** Manual

**Given** An existing single-payer expense "Transport" AED 80, paid by PlayerA, 4 participants.

**When** I edit it, toggle multi-payer on, set A=50 / B=30, and save.

**Then** the expense updates to multi-payer. The `paysplit_expense_payers` table gains 2 rows for that expense. The `paid_player_id` column becomes NULL. Balance tab shows proportional debts.

---

### TC018
**Priority:** P1 | **Status:** Manual

**Given** I am editing an expense with amount 100, 4 participants.

**When** I change the amount to 120, keep 4 participants, and save.

**Then** each participant's share updates to 30.00 (120 / 4). No validation error (amount > 0, participants selected, payer set).

---

## Section 4 — Delete Expense

### TC019
**Priority:** P0 | **Status:** Manual

**Given** There are 2 expenses: Expense1 AED 100 (A pays, split A/B/C/D) and Expense2 AED 40 (B pays, split A/B).

**When** I delete Expense1 via the confirmation modal ("Yes, Delete").

**Then** the Activities list shows only Expense2. The Balance tab recalculates to reflect only Expense2 debts: A owes B AED 20 (40/2 = 20, A is non-payer participant).

---

### TC020
**Priority:** P0 | **Status:** Manual

**Given** A multi-payer expense (payers A=60, B=40, 4 participants) exists in the DB.

**When** I delete that expense.

**Then** the `paysplit_expense_payers` rows cascade-delete (verified by checking Balance tab shows no debts from this expense). No orphan rows remain.

---

## Section 5 — Balance Tab

### TC021
**Priority:** P0 | **Status:** Manual

**Given** Single expense: A pays AED 100, split equally among A, B, C, D (4 people).
- Each share = 25. B owes A 25. C owes A 25. D owes A 25.
- "Simplify Debts" toggle is ON.

**When** I open the Balance tab.

**Then** 3 edges are shown: B → A (25), C → A (25), D → A (25). Total transactions = 3 (already minimum — no cross-debt to simplify). "Simplify" does not change anything in this single-payer case.

---

### TC022
**Priority:** P1 | **Status:** Manual

**Given** Two expenses:
- Expense1: A pays 60, participants A+B (B owes A 30)
- Expense2: B pays 40, participants A+B (A owes B 20)
- "Simplify Debts" is OFF.

**When** I open the Balance tab.

**Then** two separate debt rows are shown as recorded: "B owes A: AED 30" and "A owes B: AED 20". When I toggle Simplify ON, the display collapses to one row: "B owes A: AED 10".

---

### TC023
**Priority:** P0 | **Status:** Manual

*(See full math trace at top of this document.)*

**Given** Multi-payer expense: AED 100, A pays 60 / B pays 40, participants A/B/C/D equally (share = 25 each). Simplify OFF.

**When** I open the Balance tab.

**Then** exactly 5 debt rows appear:
- B owes A: AED 5.00
- C owes A: AED 15.00
- C owes B: AED 10.00
- D owes A: AED 15.00
- D owes B: AED 10.00

When I toggle Simplify ON, the greedy algorithm runs on net positions (A +35, B +15, C −25, D −25):
- D → A: 25 (D's 25 clears against A's 35; A left with 10)
- C → A: 10 (C's 25 clears A's remaining 10; C left with 15)
- C → B: 15 (C's 15 clears B's 15)
Result: 3 edges instead of 5.

---

### TC024
**Priority:** P1 | **Status:** Manual

**Given** Opening balance: Player C "owes" AED 50 (set by manager via v19). No other expenses.
Simplify ON.

**When** I open the Balance tab.

**Then** the settle-up includes the opening balance. Edge: C → Club Pool (in unsimplified view). In simplified view, the pool is folded in: C owes the group 50 distributed to other players if there are corresponding "gets" opening balances; or "Club Pool" appears as a party if no counterparty exists in the netMap.

---

### TC025
**Priority:** P1 | **Status:** Manual

**Given** Wallet contributions: A contributed AED 100. Wallet expense: "Court Rent" AED 80, 4 participants (A/B/C/D, share = 20 each).
- FIFO: A's 100 consumed 80 → 20 remaining.
- walletNets: A net = +80 (FIFO consumed 80 from A's contribution) − 20 (A's own share) = +60.
  B net = −20, C net = −20, D net = −20. Sum = 0 ✓
Simplify ON.

**When** I open Balance tab.

**Then** edges: B → A 20, C → A 20, D → A 20 (3 edges). The wallet net position is correctly included.

---

### TC026
**Priority:** P1 | **Status:** Manual

**Given** All balances are settled (or no expenses exist).

**When** I open the Balance tab.

**Then** "All settled!" (or equivalent empty-state message) is shown. No debt rows appear.

---

## Section 6 — Wallet Tab

### TC027
**Priority:** P1 | **Status:** Manual

**Given** I am a club member on the Wallet tab.

**When** I tap "Add Contribution", select PlayerA, enter AED 50, and save.

**Then** a new contribution row for PlayerA AED 50.00 appears in the "Active Contributions" list. Wallet total balance increases by 50.

---

### TC028
**Priority:** P1 | **Status:** Manual

**Given** Two contributions in order: C1 (PlayerA, AED 30, contributed first) and C2 (PlayerB, AED 50, contributed second). One wallet expense AED 25.

**When** I view the Wallet tab.

**Then** FIFO allocation deducts 25 from C1 (oldest). C1 remaining = 5. C2 remaining = 50. C1 shows as partially consumed with the wallet expense listed under its "consumed by" breakdown.

---

### TC029
**Priority:** P1 | **Status:** Manual

**Given** Contribution C1 (PlayerA AED 40), wallet expense AED 15.

**When** I view the Wallet tab.

**Then** C1 shows remaining = AED 25.00 (40 − 15) and "consumed by" lists the wallet expense at AED 15. C1 remains in the Active Contributions section (remaining > 0.005).

---

### TC030
**Priority:** P1 | **Status:** Manual

**Given** Contribution C1 (PlayerA AED 30), wallet expense AED 30 (fully consumes C1).

**When** I view the Wallet tab.

**Then** C1 no longer appears in Active Contributions. It appears in the "Consumed Contributions" section with remaining = 0.

---

## Section 7 — Insights / Totals Tab

### TC031
**Priority:** P2 | **Status:** Manual

**Given** Three expenses: facility AED 100, food AED 50, facility AED 50. Total = 200.

**When** I open the Totals (Insights) tab and view the category breakdown.

**Then** facility shows 75% (150/200), food shows 25% (50/200). Bar widths or percentages reflect these values.

---

### TC032
**Priority:** P2 | **Status:** Manual

**Given** Expenses spread across the last 3 calendar months.

**When** I view the monthly trend section.

**Then** three month bars appear (most recent month first). Each bar height is proportional to that month's total. Months with no expenses show AED 0.00 (or are absent from the trend list).

---

### TC033
**Priority:** P2 | **Status:** Manual

**Given** All expenses for the club total AED 1,245.50.

**When** I view the "All-time total" figure on the Totals tab.

**Then** the displayed value matches the sum: "AED 1,245.50". The year-to-date figure shows only expenses with `expense_date` in the current year.

---

## Section 8 — Notes Tab

### TC034
**Priority:** P2 | **Status:** Manual

**Given** I am a club member on the Notes tab.

**When** I type "Remember to collect from late payers" and tap Add Note.

**Then** the note appears at the top of the notes list with my name and a "just now" timestamp. The text input clears.

---

### TC035
**Priority:** P2 | **Status:** Manual

**Given** I previously added a note.

**When** I tap Delete (trash icon) on my note and confirm.

**Then** the note is removed from the list immediately (optimistic removal from `notes.value`).

---

### TC036
**Priority:** P2 | **Status:** Manual

**Given** PlayerB (not a manager) added a note. I am logged in as PlayerC (not a manager).

**When** I view the Notes tab.

**Then** the delete button is not visible on PlayerB's note. I can only delete my own notes. (Note: v12 schema changed the DELETE policy to "creator or manager" — so a non-creator non-manager cannot delete others' notes.)

---

## Section 9 — Opening Balances

### TC037
**Priority:** P1 | **Status:** Manual

**Given** The club has opening balances set for some players.

**When** I open the PaySplits Activities tab (or the Balance tab).

**Then** the Opening Balances section is collapsed by default (not expanded on first render).

---

### TC038
**Priority:** P1 | **Status:** Manual

**Given** Opening balances are collapsed.

**When** I tap the Opening Balances section header.

**Then** the section expands to show per-player rows with player name, amount (positive = "gets back", negative = "owes"), and notes. The expand/collapse state toggles correctly on repeated taps.

---

### TC039
**Priority:** P1 | **Status:** Manual

**Given** Opening balances: PlayerA gets AED 100, PlayerB owes AED 60, PlayerC gets AED 40, PlayerD owes AED 80.
Net sum = 100 − 60 + 40 − 80 = 0.

**When** I view the summary ribbon / totals.

**Then** the net total shown matches the sum of all opening balance amounts. If the sum is non-zero, a warning is displayed indicating the opening balances don't net to zero.

---

### TC040
**Priority:** P1 | **Status:** Manual

**Given** PlayerA has an opening balance of AED +50 (gets back).

**When** I (as manager) tap Edit on PlayerA's row, change the amount to AED +80, and save.

**Then** `set_opening_balance` is called with the updated amount. PlayerA's row shows AED +80.00. The Balance tab recalculates settle-up with the new value.

---

## Section 10 — Edge Cases

### TC041
**Priority:** P1 | **Status:** Manual

**Given** A new club with 0 expenses, 0 wallet contributions, 0 opening balances, 0 notes.

**When** I navigate to PaySplits.

**Then** the app does not crash. Each tab shows an appropriate empty state (e.g., "No expenses yet", "All settled!", "No contributions yet").

---

### TC042
**Priority:** P2 | **Status:** Manual

**Given** A club with only 1 active player.

**When** I add an expense with that player as payer and sole participant, then view the Balance tab.

**Then** no debt rows are shown (the payer and sole participant are the same person — excluded by `pa.player_id <> e.paid_player_id` in the SQL). "All settled!" is shown.

---

### TC043
**Priority:** P1 | **Status:** Manual

**Given** I am a member of two clubs (Club Alpha, Club Beta), each with different expenses.

**When** I switch the active club from Club Alpha to Club Beta using the club switcher.

**Then** all PaySplits data (expenses, balances, wallet, opening balances, notes) reloads for Club Beta. Club Alpha data is not visible. The `expandedPlayer` selection resets.

---

### TC044
**Priority:** P2 | **Status:** Manual

**Given** I am on the Add Expense form.

**When** I enter a very large amount: 99999.99, select 1 participant, fill title, select payer, and save.

**Then** the expense saves without overflow or rounding errors. The Activities list shows "AED 99,999.99". The Balance tab shows the participant owes AED 99,999.99 to the payer. No truncation or display glitch.

---

### TC045
**Priority:** P1 | **Status:** Manual

**Given** A manager sets an opening balance for PlayerD: direction = "owes", amount = AED 75 (stored as −75.00).

**When** I (any member) view the Opening Balances section on the Balance tab.

**Then** PlayerD's row displays the negative amount in a rose/red color to distinguish it from positive balances. The amount reads "−AED 75.00" or "AED 75.00 (owes)". The settle-up algorithm treats PlayerD as a net ower with net = −75.

---

## Appendix — Test Data Setup

For manual testing, create a club with 4 players (A, B, C, D) where:
- All 4 are active.
- Current user is mapped to Player A.
- Current user has owner or manager role for tests requiring write access to opening balances and wallet management.

Supabase SQL to verify after TC023:
```sql
-- Confirm paysplit_expense_payers rows
SELECT pep.player_id, p.display_name, pep.amount
FROM paysplit_expense_payers pep
JOIN players p ON p.id = pep.player_id
WHERE pep.expense_id = '<expense_id>';

-- Confirm get_balance_summary output
SELECT * FROM get_balance_summary('<club_id>');
```
