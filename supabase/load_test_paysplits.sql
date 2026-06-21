-- =====================================================================
-- Badminton 360 — PaySplits Load Test Data Generator
-- Generates realistic large-dataset to stress-test PaySplits performance.
--
-- Prerequisites: at least one club must exist in the database.
-- Run in Supabase SQL Editor (or psql).
--
-- Generates:
--   50 active players in the first club
--   10,000 paysplit_expenses spread over 24 months
--   ~100,000 paysplit_participants rows (avg 10 participants per expense)
--   5,000 wallet_contributions
--   50 paysplit_opening_balances (one per player, overwritten in the loop)
-- =====================================================================

DO $$
DECLARE
  v_club_id       uuid;
  v_owner_id      uuid;
  v_player_ids    uuid[];
  v_player_id     uuid;
  v_expense_id    uuid;
  v_contrib_id    uuid;
  v_player_count  int := 50;
  v_expense_count int := 10000;
  v_wallet_count  int := 5000;
  i               int;
  j               int;
  v_payer_idx     int;
  v_num_parts     int;
  v_part_ids      uuid[];
  v_share         numeric;
  v_amount        numeric;
  v_date          date;
  v_category      text;
  v_from_wallet   boolean;
  categories      text[] := ARRAY['facility','food','drinks','equipment','transport','tax','other'];
  v_display_name  text;
BEGIN

  -- ── 1. Pick the first available club ──────────────────────────────────
  SELECT id INTO v_club_id FROM clubs ORDER BY created_at LIMIT 1;
  IF v_club_id IS NULL THEN
    RAISE EXCEPTION 'No clubs found. Create a club first before running this script.';
  END IF;
  RAISE NOTICE 'Using club_id: %', v_club_id;

  -- Pick the club owner as the auth user for created_by columns
  SELECT user_id INTO v_owner_id
  FROM club_members
  WHERE club_id = v_club_id AND role = 'owner'
  LIMIT 1;
  IF v_owner_id IS NULL THEN
    -- Fall back to any member
    SELECT user_id INTO v_owner_id
    FROM club_members WHERE club_id = v_club_id LIMIT 1;
  END IF;
  RAISE NOTICE 'Using owner/creator user_id: %', v_owner_id;

  -- ── 2. Generate 50 test players ────────────────────────────────────────
  RAISE NOTICE 'Creating % test players...', v_player_count;
  v_player_ids := ARRAY[]::uuid[];

  FOR i IN 1..v_player_count LOOP
    v_display_name := 'LoadTest Player ' || i;

    -- Insert or re-use existing test player by display_name
    INSERT INTO players (club_id, display_name, elo, is_active, created_at)
    VALUES (
      v_club_id,
      v_display_name,
      900 + (random() * 300)::int,  -- Elo 900–1200
      true,
      now() - (random() * interval '730 days')
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_player_id;

    -- If conflict (already exists), look it up
    IF v_player_id IS NULL THEN
      SELECT id INTO v_player_id
      FROM players
      WHERE club_id = v_club_id AND display_name = v_display_name
      LIMIT 1;
    END IF;

    IF v_player_id IS NOT NULL THEN
      v_player_ids := v_player_ids || v_player_id;
    END IF;
  END LOOP;

  RAISE NOTICE 'Players ready: % ids', array_length(v_player_ids, 1);

  IF array_length(v_player_ids, 1) = 0 THEN
    RAISE EXCEPTION 'No player ids collected. Check players table.';
  END IF;

  -- ── 3. Generate 10,000 expenses over 24 months ─────────────────────────
  RAISE NOTICE 'Inserting % expenses...', v_expense_count;

  FOR i IN 1..v_expense_count LOOP
    -- Random date within last 24 months
    v_date     := current_date - (random() * 730)::int;
    v_amount   := ROUND((10 + random() * 490)::numeric, 2);  -- 10–500 AED
    v_category := categories[1 + (random() * (array_length(categories,1) - 1))::int];

    -- ~20% of expenses paid from wallet
    v_from_wallet := (random() < 0.20);

    -- Random payer index
    v_payer_idx := 1 + (random() * (array_length(v_player_ids,1) - 1))::int;

    -- Random participant subset: 3–15 players
    v_num_parts := 3 + (random() * 12)::int;
    v_num_parts := LEAST(v_num_parts, array_length(v_player_ids,1));

    -- Build participant array (random shuffle via ORDER BY random())
    SELECT array_agg(pid) INTO v_part_ids
    FROM (
      SELECT unnest(v_player_ids) AS pid
      ORDER BY random()
      LIMIT v_num_parts
    ) sub;

    v_share := ROUND(v_amount / v_num_parts, 2);

    -- Insert expense
    INSERT INTO paysplit_expenses (
      club_id, title, category, amount,
      paid_player_id, paid_from_wallet,
      expense_date, notes, created_by, created_at, updated_at
    ) VALUES (
      v_club_id,
      'Load Test ' || v_category || ' #' || i,
      v_category,
      v_amount,
      CASE WHEN v_from_wallet THEN NULL
           ELSE v_player_ids[v_payer_idx] END,
      v_from_wallet,
      v_date,
      CASE WHEN (random() < 0.3) THEN 'Auto-generated test expense' ELSE NULL END,
      v_owner_id,
      (v_date::timestamptz + (random() * interval '8 hours')),
      (v_date::timestamptz + (random() * interval '8 hours'))
    )
    RETURNING id INTO v_expense_id;

    -- Insert participants
    INSERT INTO paysplit_participants (expense_id, player_id, share_amount)
    SELECT v_expense_id, unnest(v_part_ids), v_share
    ON CONFLICT (expense_id, player_id) DO NOTHING;

  END LOOP;

  RAISE NOTICE 'Expenses inserted.';

  -- ── 4. Generate 5,000 wallet contributions ─────────────────────────────
  RAISE NOTICE 'Inserting % wallet contributions...', v_wallet_count;

  FOR i IN 1..v_wallet_count LOOP
    v_payer_idx := 1 + (random() * (array_length(v_player_ids,1) - 1))::int;
    v_amount    := ROUND((50 + random() * 450)::numeric, 2);  -- 50–500 AED
    v_date      := current_date - (random() * 730)::int;

    INSERT INTO wallet_contributions (
      club_id, player_id, amount, notes, created_by, contributed_at, created_at
    ) VALUES (
      v_club_id,
      v_player_ids[v_payer_idx],
      v_amount,
      CASE WHEN (random() < 0.2) THEN 'Load test contribution' ELSE NULL END,
      v_owner_id,
      (v_date::timestamptz + (random() * interval '12 hours')),
      (v_date::timestamptz + (random() * interval '12 hours'))
    );
  END LOOP;

  RAISE NOTICE 'Wallet contributions inserted.';

  -- ── 5. Generate opening balances (one per player — upsert) ─────────────
  -- Each player gets a balance between -500 and +500 AED (excluding near-zero)
  RAISE NOTICE 'Setting opening balances for all % test players...', array_length(v_player_ids,1);

  FOREACH v_player_id IN ARRAY v_player_ids LOOP
    -- Random non-zero amount: -500 to -10 or +10 to +500
    v_amount := ROUND(
      CASE WHEN random() < 0.5
        THEN -(10 + random() * 490)
        ELSE  (10 + random() * 490)
      END::numeric,
      2
    );

    INSERT INTO paysplit_opening_balances (
      club_id, player_id, amount, notes, created_by, created_at, updated_at
    ) VALUES (
      v_club_id,
      v_player_id,
      v_amount,
      'Migration opening balance (load test)',
      v_owner_id,
      now(),
      now()
    )
    ON CONFLICT (club_id, player_id)
    DO UPDATE SET
      amount     = EXCLUDED.amount,
      notes      = EXCLUDED.notes,
      updated_at = now();
  END LOOP;

  RAISE NOTICE 'Opening balances set.';

  -- ── Summary ────────────────────────────────────────────────────────────
  RAISE NOTICE '=== Load Test Data Summary ===';
  RAISE NOTICE 'Club ID: %', v_club_id;
  RAISE NOTICE 'Players:       %', (SELECT COUNT(*) FROM players WHERE club_id = v_club_id AND display_name LIKE 'LoadTest Player%');
  RAISE NOTICE 'Expenses:      %', (SELECT COUNT(*) FROM paysplit_expenses WHERE club_id = v_club_id);
  RAISE NOTICE 'Participants:  %', (SELECT COUNT(*) FROM paysplit_participants pp JOIN paysplit_expenses e ON e.id = pp.expense_id WHERE e.club_id = v_club_id);
  RAISE NOTICE 'Wallet contribs: %', (SELECT COUNT(*) FROM wallet_contributions WHERE club_id = v_club_id);
  RAISE NOTICE 'Opening bals:  %', (SELECT COUNT(*) FROM paysplit_opening_balances WHERE club_id = v_club_id);

END $$;
