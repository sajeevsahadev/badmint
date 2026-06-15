-- =====================================================================
-- Badmint v31 — GDPR Account Deletion
-- Run once in Supabase SQL Editor after v30_schema.sql
-- =====================================================================

-- Allow NULL on created_by / registered_by in operational tables so that
-- admin.deleteUser() doesn't fail on FK constraint violations.
-- Records are preserved for club integrity; only the user link is removed.
ALTER TABLE matches                   ALTER COLUMN created_by    DROP NOT NULL;
ALTER TABLE paysplit_expenses         ALTER COLUMN created_by    DROP NOT NULL;
ALTER TABLE paysplit_notes            ALTER COLUMN created_by    DROP NOT NULL;
ALTER TABLE wallet_contributions      ALTER COLUMN created_by    DROP NOT NULL;
ALTER TABLE tournaments               ALTER COLUMN created_by    DROP NOT NULL;
ALTER TABLE tournament_registrations  ALTER COLUMN registered_by DROP NOT NULL;

-- club_invites.invited_by — may already be nullable in some environments
DO $$ BEGIN
  ALTER TABLE club_invites ALTER COLUMN invited_by DROP NOT NULL;
EXCEPTION WHEN others THEN NULL; END $$;

-- ── RPC: check_can_delete_account ─────────────────────────────────────
-- Returns {can_delete: bool, reason: text, details: text}
-- Hard blocks: club owner, match history, wallet balance, paysplit debt
DROP FUNCTION IF EXISTS check_can_delete_account();
CREATE OR REPLACE FUNCTION check_can_delete_account()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid              uuid := auth.uid();
  v_owner_clubs    text;
  v_match_count    int;
  v_wallet_balance numeric;
  v_split_balance  numeric;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('can_delete', false, 'reason', 'unauthenticated', 'details', 'Not signed in.');
  END IF;

  -- 1. Club owner check ────────────────────────────────────────────────────
  SELECT string_agg(c.name, ', ' ORDER BY c.name) INTO v_owner_clubs
  FROM club_members cm
  JOIN clubs c ON c.id = cm.club_id
  WHERE cm.user_id = uid AND cm.role = 'owner';

  IF v_owner_clubs IS NOT NULL THEN
    RETURN jsonb_build_object(
      'can_delete', false,
      'reason',  'club_owner',
      'details', 'You own: ' || v_owner_clubs || '. Transfer ownership or delete the club first, then try again.'
    );
  END IF;

  -- 2. Match history check ─────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_match_count
  FROM match_participants mp
  JOIN players p ON p.id = mp.player_id
  WHERE p.user_id = uid;

  IF v_match_count > 0 THEN
    RETURN jsonb_build_object(
      'can_delete', false,
      'reason',  'match_history',
      'details', format(
        'You have %s match(es) recorded across your clubs. '
        'Ask your manager to mark your player profile as Inactive instead of deleting your account.',
        v_match_count)
    );
  END IF;

  -- 3. Wallet balance check (club owes user money) ─────────────────────────
  WITH user_pids AS (SELECT id FROM players WHERE user_id = uid),
  contrib AS (
    SELECT wc.player_id, SUM(wc.amount) AS total
    FROM wallet_contributions wc
    WHERE wc.player_id IN (SELECT id FROM user_pids)
    GROUP BY wc.player_id
  ),
  consumed AS (
    SELECT pa.player_id, SUM(pa.share_amount) AS total
    FROM paysplit_participants pa
    JOIN paysplit_expenses e ON e.id = pa.expense_id AND e.paid_from_wallet = true
    WHERE pa.player_id IN (SELECT id FROM user_pids)
    GROUP BY pa.player_id
  )
  SELECT GREATEST(COALESCE(SUM(c.total - COALESCE(d.total, 0)), 0), 0)
  INTO v_wallet_balance
  FROM contrib c LEFT JOIN consumed d ON d.player_id = c.player_id;

  IF COALESCE(v_wallet_balance, 0) > 0.01 THEN
    RETURN jsonb_build_object(
      'can_delete', false,
      'reason',  'wallet_balance',
      'details', format(
        'You have %.2f remaining in a Club Wallet. Ask your manager to refund this balance first.',
        v_wallet_balance)
    );
  END IF;

  -- 4. PaySplit pairwise balance check ─────────────────────────────────────
  WITH user_pids AS (SELECT id FROM players WHERE user_id = uid),
  raw AS (
    SELECT pa.player_id AS debtor, e.paid_player_id AS creditor, pa.share_amount AS amt
    FROM paysplit_expenses e
    JOIN paysplit_participants pa ON pa.expense_id = e.id
    WHERE e.paid_from_wallet = false
      AND pa.player_id <> e.paid_player_id
      AND (pa.player_id IN (SELECT id FROM user_pids)
        OR e.paid_player_id IN (SELECT id FROM user_pids))
  ),
  netted AS (
    SELECT
      LEAST(debtor, creditor)    AS p_lo,
      GREATEST(debtor, creditor) AS p_hi,
      SUM(CASE WHEN debtor < creditor THEN amt ELSE -amt END) AS net
    FROM raw
    GROUP BY LEAST(debtor, creditor), GREATEST(debtor, creditor)
  )
  SELECT COALESCE(SUM(ABS(net)), 0)
  INTO v_split_balance
  FROM netted
  WHERE (p_lo IN (SELECT id FROM user_pids) OR p_hi IN (SELECT id FROM user_pids))
    AND ABS(net) >= 0.01;

  IF COALESCE(v_split_balance, 0) > 0.01 THEN
    RETURN jsonb_build_object(
      'can_delete', false,
      'reason',  'paysplit_balance',
      'details', 'You have an outstanding PaySplit balance. Settle all club debts before deleting your account.'
    );
  END IF;

  RETURN jsonb_build_object('can_delete', true, 'reason', '', 'details', '');
END;
$$;

-- ── RPC: delete_account_data ──────────────────────────────────────────
-- Deletes PII, unlinking players, clearing created_by on operational records.
-- The auth.users row is then deleted by the delete-account Edge Function.
DROP FUNCTION IF EXISTS delete_account_data();
CREATE OR REPLACE FUNCTION delete_account_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid     uuid := auth.uid();
  v_check jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- Re-run checks atomically (prevents race condition / UI bypass)
  v_check := check_can_delete_account();
  IF NOT (v_check->>'can_delete')::boolean THEN
    RAISE EXCEPTION '%', v_check->>'details';
  END IF;

  -- Nullify created_by on operational records (preserve club history)
  UPDATE matches                  SET created_by    = NULL WHERE created_by    = uid;
  UPDATE paysplit_notes           SET created_by    = NULL WHERE created_by    = uid;
  UPDATE wallet_contributions     SET created_by    = NULL WHERE created_by    = uid;
  UPDATE tournaments              SET created_by    = NULL WHERE created_by    = uid;
  UPDATE tournament_registrations SET registered_by = NULL WHERE registered_by = uid;
  UPDATE club_invites             SET invited_by    = NULL WHERE invited_by    = uid;

  -- Delete the user's own expenses (settled balance confirmed by check above)
  DELETE FROM paysplit_expenses WHERE created_by = uid;

  -- Unlink player records (player stays for match/Elo history; account is removed)
  UPDATE players SET user_id = NULL WHERE user_id = uid;

  -- Delete all personal data (PII)
  DELETE FROM user_profiles      WHERE user_id = uid;
  DELETE FROM club_members       WHERE user_id = uid;
  DELETE FROM join_requests      WHERE user_id = uid;
  DELETE FROM app_sessions       WHERE user_id = uid;
  DELETE FROM activity_log       WHERE user_id = uid;
  DELETE FROM push_subscriptions WHERE user_id = uid;
  DELETE FROM app_roles          WHERE user_id = uid;
END;
$$;

GRANT EXECUTE ON FUNCTION check_can_delete_account() TO authenticated;
GRANT EXECUTE ON FUNCTION delete_account_data()       TO authenticated;
