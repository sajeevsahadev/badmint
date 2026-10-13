-- =====================================================================
-- Badminton 360 v129 — Account lifecycle & GDPR
-- Applied to prod via Supabase MCP; archived here for rebuild parity.
--
-- Delivers:
--   1. email_suppression  — no-login unsubscribe list (keyed by email, survives deletion)
--   2. user_profiles.deactivated_at — "pause account": data stays, zero automated email
--   3. Comprehensive erasure (_erase_user) covering EVERY user-referencing column
--      (v31 missed chat, biometric creds, tournament results, settlements, etc.)
--   4. Anonymize-on-delete: match history no longer blocks erasure — the player row is
--      unlinked (matches preserved for other players' Elo), account fully removed.
--   5. Admin controls: admin_set_user_active (deactivate/reactivate), admin_erase_user.
--   6. get_pending_nudges + get_all_users updated for deactivation/suppression.
-- =====================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1. EMAIL SUPPRESSION (GDPR no-login unsubscribe)
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS email_suppression (
  email      text PRIMARY KEY,          -- always stored lowercased
  reason     text,
  source     text,                      -- 'unsubscribe' | 'admin' | 'bounce'
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE email_suppression ENABLE ROW LEVEL SECURITY;
-- No policies: only service_role (senders) + SECURITY DEFINER helpers touch it.

CREATE OR REPLACE FUNCTION is_email_suppressed(p_email text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM email_suppression WHERE email = lower(p_email));
$$;
REVOKE ALL ON FUNCTION is_email_suppressed(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION is_email_suppressed(text) TO service_role;

-- Add/refresh a suppression entry (public unsubscribe Edge Function calls this via service role)
CREATE OR REPLACE FUNCTION suppress_email(p_email text, p_reason text DEFAULT 'unsubscribe', p_source text DEFAULT 'unsubscribe')
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO email_suppression(email, reason, source)
  VALUES (lower(p_email), p_reason, p_source)
  ON CONFLICT (email) DO UPDATE SET reason = excluded.reason, source = excluded.source, created_at = now();
$$;
REVOKE ALL ON FUNCTION suppress_email(text,text,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION suppress_email(text,text,text) TO service_role;

-- A signed-in user re-opting-in (removes their own suppression) — used by Email Settings
CREATE OR REPLACE FUNCTION resubscribe_my_email()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_email text;
BEGIN
  SELECT email INTO v_email FROM auth.users WHERE id = auth.uid();
  IF v_email IS NOT NULL THEN DELETE FROM email_suppression WHERE email = lower(v_email); END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION resubscribe_my_email() TO authenticated;

-- Is the signed-in user's own email currently suppressed? (Email Settings badge)
CREATE OR REPLACE FUNCTION am_i_suppressed()
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_email text;
BEGIN
  SELECT email INTO v_email FROM auth.users WHERE id = auth.uid();
  RETURN v_email IS NOT NULL AND EXISTS (SELECT 1 FROM email_suppression WHERE email = lower(v_email));
END;
$$;
GRANT EXECUTE ON FUNCTION am_i_suppressed() TO authenticated;

-- Centralised send gate for Edge senders: suppression + deactivation + a single pref key
CREATE OR REPLACE FUNCTION can_email_user(p_user_id uuid, p_pref text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_email text; v_deact timestamptz; v_prefs jsonb;
BEGIN
  SELECT u.email, up.deactivated_at, up.email_prefs
    INTO v_email, v_deact, v_prefs
  FROM auth.users u LEFT JOIN user_profiles up ON up.user_id = u.id
  WHERE u.id = p_user_id;
  IF v_email IS NULL THEN RETURN false; END IF;              -- deleted / unknown
  IF v_deact IS NOT NULL THEN RETURN false; END IF;          -- deactivated
  IF EXISTS (SELECT 1 FROM email_suppression WHERE email = lower(v_email)) THEN RETURN false; END IF;
  IF p_pref IS NOT NULL AND NOT COALESCE((v_prefs->>p_pref)::boolean, true) THEN RETURN false; END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION can_email_user(uuid, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION can_email_user(uuid, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2. DEACTIVATION  (account stays, all automated email stops)
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS deactivated_at timestamptz;

CREATE OR REPLACE FUNCTION deactivate_my_account()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  INSERT INTO user_profiles(user_id, deactivated_at, updated_at)
    VALUES (auth.uid(), now(), now())
  ON CONFLICT (user_id) DO UPDATE SET deactivated_at = now(), updated_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION deactivate_my_account() TO authenticated;

CREATE OR REPLACE FUNCTION reactivate_my_account()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE user_profiles SET deactivated_at = NULL, updated_at = now() WHERE user_id = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION reactivate_my_account() TO authenticated;

CREATE OR REPLACE FUNCTION admin_set_user_active(p_user_id uuid, p_active boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  INSERT INTO user_profiles(user_id, deactivated_at, updated_at)
    VALUES (p_user_id, CASE WHEN p_active THEN NULL ELSE now() END, now())
  ON CONFLICT (user_id) DO UPDATE
    SET deactivated_at = CASE WHEN p_active THEN NULL ELSE now() END, updated_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION admin_set_user_active(uuid, boolean) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 3. ERASURE  — make shared NOT NULL author columns nullable so the person
--    can be unlinked while the shared record is preserved.
-- ─────────────────────────────────────────────────────────────────────
DO $$ BEGIN ALTER TABLE clubs                     ALTER COLUMN created_by DROP NOT NULL; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE club_schedule             ALTER COLUMN created_by DROP NOT NULL; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE schedule_attendees        ALTER COLUMN added_by   DROP NOT NULL; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE live_match_points         ALTER COLUMN scored_by  DROP NOT NULL; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE paysplit_opening_balances ALTER COLUMN created_by DROP NOT NULL; EXCEPTION WHEN others THEN NULL; END $$;

-- Internal: wipe one user everywhere. Caller is responsible for block checks + auth.users deletion.
CREATE OR REPLACE FUNCTION _erase_user(p_uid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_uid IS NULL THEN RAISE EXCEPTION 'No user id'; END IF;

  -- (a) Nullify authorship on shared/operational records (preserve club history)
  UPDATE matches                  SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE paysplit_notes           SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE wallet_contributions     SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE paysplit_settlements     SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE paysplit_opening_balances SET created_by      = NULL WHERE created_by       = p_uid;
  UPDATE tournaments              SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE tournament_registrations SET registered_by    = NULL WHERE registered_by    = p_uid;
  UPDATE tournament_registrations SET player_a_user_id = NULL WHERE player_a_user_id = p_uid;
  UPDATE tournament_registrations SET player_b_user_id = NULL WHERE player_b_user_id = p_uid;
  UPDATE tournament_photos        SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE tournament_admins        SET added_by         = NULL WHERE added_by         = p_uid;
  UPDATE club_invites             SET invited_by       = NULL WHERE invited_by       = p_uid;
  UPDATE app_roles                SET granted_by       = NULL WHERE granted_by       = p_uid;
  UPDATE app_settings             SET updated_by       = NULL WHERE updated_by       = p_uid;
  UPDATE facilities               SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE facility_bookings        SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE session_plans            SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE live_matches             SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE live_match_points        SET scored_by        = NULL WHERE scored_by        = p_uid;
  UPDATE clubs                    SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE club_schedule            SET created_by       = NULL WHERE created_by       = p_uid;
  UPDATE schedule_attendees       SET added_by         = NULL WHERE added_by         = p_uid;

  -- (b) Delete the user's own expenses (settled balance confirmed by block check)
  DELETE FROM paysplit_expenses WHERE created_by = p_uid;

  -- (c) Anonymize: unlink player rows (matches/Elo preserved, shown as guest)
  UPDATE players SET user_id = NULL WHERE user_id = p_uid;

  -- (d) Delete all personal rows (PII + personal activity)
  DELETE FROM club_message_reactions   WHERE user_id = p_uid;           -- own reactions on others' msgs
  DELETE FROM club_message_stars       WHERE user_id = p_uid;
  DELETE FROM club_chat_reads          WHERE user_id = p_uid;
  DELETE FROM club_messages            WHERE user_id = p_uid;           -- cascades reactions/stars on them
  DELETE FROM schedule_votes           WHERE user_id = p_uid;
  DELETE FROM player_tournament_results WHERE user_id = p_uid;
  DELETE FROM tournament_admins        WHERE user_id = p_uid;
  DELETE FROM webauthn_credentials     WHERE user_id = p_uid;
  DELETE FROM user_profiles            WHERE user_id = p_uid;
  DELETE FROM club_members             WHERE user_id = p_uid;
  DELETE FROM join_requests            WHERE user_id = p_uid;
  DELETE FROM app_sessions             WHERE user_id = p_uid;
  DELETE FROM activity_log             WHERE user_id = p_uid;
  DELETE FROM push_subscriptions       WHERE user_id = p_uid;
  DELETE FROM app_roles                WHERE user_id = p_uid;
  DELETE FROM lifecycle_email_log      WHERE user_id = p_uid;
END;
$$;
REVOKE ALL ON FUNCTION _erase_user(uuid) FROM public, anon, authenticated;

-- Internal: can this user be hard-deleted? Blocks: club owner, wallet owed, paysplit debt.
-- Match history NO LONGER blocks (anonymized on delete) — returned as info only.
CREATE OR REPLACE FUNCTION _can_delete_user(p_uid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_owner_clubs    text;
  v_match_count    int;
  v_wallet_balance numeric;
  v_split_balance  numeric;
BEGIN
  -- 1. Club owner
  SELECT string_agg(c.name, ', ' ORDER BY c.name) INTO v_owner_clubs
  FROM club_members cm JOIN clubs c ON c.id = cm.club_id
  WHERE cm.user_id = p_uid AND cm.role = 'owner';
  IF v_owner_clubs IS NOT NULL THEN
    RETURN jsonb_build_object('can_delete', false, 'reason','club_owner',
      'details', 'Owns club(s): ' || v_owner_clubs || '. Transfer ownership or delete the club first.');
  END IF;

  -- 2. Wallet balance (club owes user)
  WITH user_pids AS (SELECT id FROM players WHERE user_id = p_uid),
  contrib AS (
    SELECT wc.player_id, SUM(wc.amount) AS total FROM wallet_contributions wc
    WHERE wc.player_id IN (SELECT id FROM user_pids) GROUP BY wc.player_id),
  consumed AS (
    SELECT pa.player_id, SUM(pa.share_amount) AS total
    FROM paysplit_participants pa
    JOIN paysplit_expenses e ON e.id = pa.expense_id AND e.paid_from_wallet = true
    WHERE pa.player_id IN (SELECT id FROM user_pids) GROUP BY pa.player_id)
  SELECT GREATEST(COALESCE(SUM(c.total - COALESCE(d.total,0)),0),0) INTO v_wallet_balance
  FROM contrib c LEFT JOIN consumed d ON d.player_id = c.player_id;
  IF COALESCE(v_wallet_balance,0) > 0.01 THEN
    RETURN jsonb_build_object('can_delete', false, 'reason','wallet_balance',
      'details', format('Has %.2f remaining in a Club Wallet. Ask the manager to refund it first.', v_wallet_balance));
  END IF;

  -- 3. PaySplit pairwise balance
  WITH user_pids AS (SELECT id FROM players WHERE user_id = p_uid),
  raw AS (
    SELECT pa.player_id AS debtor, e.paid_player_id AS creditor, pa.share_amount AS amt
    FROM paysplit_expenses e JOIN paysplit_participants pa ON pa.expense_id = e.id
    WHERE e.paid_from_wallet = false AND pa.player_id <> e.paid_player_id
      AND (pa.player_id IN (SELECT id FROM user_pids) OR e.paid_player_id IN (SELECT id FROM user_pids))),
  netted AS (
    SELECT LEAST(debtor,creditor) p_lo, GREATEST(debtor,creditor) p_hi,
           SUM(CASE WHEN debtor<creditor THEN amt ELSE -amt END) net
    FROM raw GROUP BY LEAST(debtor,creditor), GREATEST(debtor,creditor))
  SELECT COALESCE(SUM(ABS(net)),0) INTO v_split_balance FROM netted
  WHERE (p_lo IN (SELECT id FROM user_pids) OR p_hi IN (SELECT id FROM user_pids)) AND ABS(net) >= 0.01;
  IF COALESCE(v_split_balance,0) > 0.01 THEN
    RETURN jsonb_build_object('can_delete', false, 'reason','paysplit_balance',
      'details', 'Has an outstanding PaySplit balance. Settle all club debts first.');
  END IF;

  -- Info: match count (anonymized, not a blocker)
  SELECT COUNT(*) INTO v_match_count
  FROM match_participants mp JOIN players p ON p.id = mp.player_id WHERE p.user_id = p_uid;

  RETURN jsonb_build_object('can_delete', true, 'reason','', 'details','', 'match_count', COALESCE(v_match_count,0));
END;
$$;
REVOKE ALL ON FUNCTION _can_delete_user(uuid) FROM public, anon, authenticated;

-- Self pre-check (wraps _can_delete_user with auth.uid) — signature unchanged, Edge Fn keeps working
CREATE OR REPLACE FUNCTION check_can_delete_account()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('can_delete', false, 'reason','unauthenticated','details','Not signed in.');
  END IF;
  RETURN _can_delete_user(auth.uid());
END;
$$;
GRANT EXECUTE ON FUNCTION check_can_delete_account() TO authenticated;

-- Self erase (re-checks atomically then wipes) — signature unchanged, Edge Fn keeps working
CREATE OR REPLACE FUNCTION delete_account_data()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); v_check jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  v_check := _can_delete_user(uid);
  IF NOT (v_check->>'can_delete')::boolean THEN RAISE EXCEPTION '%', v_check->>'details'; END IF;
  PERFORM _erase_user(uid);
END;
$$;
GRANT EXECUTE ON FUNCTION delete_account_data() TO authenticated;

-- Admin erase (service_role only; the admin-delete-user Edge Fn verifies caller is app_admin first,
-- then deletes the auth.users row). Returns the block jsonb if not deletable.
CREATE OR REPLACE FUNCTION admin_erase_user(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_check jsonb;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'No user id'; END IF;
  v_check := _can_delete_user(p_user_id);
  IF NOT (v_check->>'can_delete')::boolean THEN RETURN v_check; END IF;
  PERFORM _erase_user(p_user_id);
  RETURN jsonb_build_object('can_delete', true, 'erased', true);
END;
$$;
REVOKE ALL ON FUNCTION admin_erase_user(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_erase_user(uuid) TO service_role;

-- Admin pre-check (callable with the admin's JWT so the UI can show blocks before confirming)
CREATE OR REPLACE FUNCTION admin_can_delete_user(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN _can_delete_user(p_user_id);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_can_delete_user(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 4. GDPR data export (right to access / portability)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION export_my_data()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); v jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT jsonb_build_object(
    'exported_at', now(),
    'account',    (SELECT jsonb_build_object('id', id, 'email', email, 'created_at', created_at,
                                              'last_sign_in_at', last_sign_in_at) FROM auth.users WHERE id = uid),
    'profile',    (SELECT to_jsonb(up) FROM user_profiles up WHERE up.user_id = uid),
    'clubs',      (SELECT jsonb_agg(jsonb_build_object('club', c.name, 'role', cm.role, 'joined_at', cm.joined_at))
                   FROM club_members cm JOIN clubs c ON c.id = cm.club_id WHERE cm.user_id = uid),
    'players',    (SELECT jsonb_agg(jsonb_build_object('display_name', p.display_name, 'elo', p.elo, 'club_id', p.club_id))
                   FROM players p WHERE p.user_id = uid),
    'match_count',(SELECT COUNT(*) FROM match_participants mp JOIN players p ON p.id = mp.player_id WHERE p.user_id = uid),
    'sessions',   (SELECT jsonb_agg(jsonb_build_object('logged_in_at', logged_in_at, 'ip', ip_address, 'ua', user_agent)
                   FROM app_sessions WHERE user_id = uid)),
    'email_prefs',(SELECT email_prefs FROM user_profiles WHERE user_id = uid),
    'push_prefs', (SELECT push_prefs  FROM user_profiles WHERE user_id = uid)
  ) INTO v;
  RETURN v;
END;
$$;
GRANT EXECUTE ON FUNCTION export_my_data() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 5. get_pending_nudges — exclude deactivated + suppressed in every branch
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_pending_nudges()
RETURNS TABLE(user_id uuid, email text, name text, kind text)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  -- Welcome: signed up in the last 2 days, not yet welcomed
  SELECT u.id, u.email::text,
         COALESCE(up.full_name, up.nickname, split_part(u.email, '@', 1)), 'welcome'::text
  FROM auth.users u LEFT JOIN user_profiles up ON up.user_id = u.id
  WHERE u.email IS NOT NULL
    AND u.created_at > now() - interval '2 days'
    AND up.deactivated_at IS NULL
    AND NOT is_email_suppressed(u.email)
    AND NOT EXISTS (SELECT 1 FROM lifecycle_email_log l WHERE l.user_id = u.id AND l.kind = 'welcome')
  UNION ALL
  -- Day-2: 2–30 days ago, still no club
  SELECT u.id, u.email::text,
         COALESCE(up.full_name, up.nickname, split_part(u.email, '@', 1)), 'day2'::text
  FROM auth.users u LEFT JOIN user_profiles up ON up.user_id = u.id
  WHERE u.email IS NOT NULL
    AND u.created_at <= now() - interval '2 days'
    AND u.created_at >  now() - interval '30 days'
    AND up.deactivated_at IS NULL
    AND NOT is_email_suppressed(u.email)
    AND COALESCE((up.email_prefs->>'news')::boolean, true)
    AND NOT EXISTS (SELECT 1 FROM club_members cm WHERE cm.user_id = u.id)
    AND NOT EXISTS (SELECT 1 FROM lifecycle_email_log l WHERE l.user_id = u.id AND l.kind = 'day2')
  UNION ALL
  -- Monthly: 30+ days, still no club
  SELECT u.id, u.email::text,
         COALESCE(up.full_name, up.nickname, split_part(u.email, '@', 1)), 'monthly'::text
  FROM auth.users u LEFT JOIN user_profiles up ON up.user_id = u.id
  WHERE u.email IS NOT NULL
    AND u.created_at <= now() - interval '30 days'
    AND up.deactivated_at IS NULL
    AND NOT is_email_suppressed(u.email)
    AND COALESCE((up.email_prefs->>'news')::boolean, true)
    AND NOT EXISTS (SELECT 1 FROM club_members cm WHERE cm.user_id = u.id)
    AND NOT EXISTS (SELECT 1 FROM lifecycle_email_log l
                    WHERE l.user_id = u.id AND l.kind = 'monthly' AND l.sent_at > now() - interval '30 days')
  LIMIT 800;
$$;
REVOKE ALL ON FUNCTION get_pending_nudges() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION get_pending_nudges() TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 6. get_all_users — expose deactivated_at + suppression for the Admin UI
-- ─────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS get_all_users(text);
CREATE OR REPLACE FUNCTION get_all_users(p_search text DEFAULT NULL)
RETURNS TABLE(user_id uuid, email text, full_name text, nickname text,
              last_sign_in timestamptz, created_at timestamptz, roles jsonb,
              tournaments_created bigint, login_count bigint, last_ip text, last_user_agent text,
              deactivated_at timestamptz, email_suppressed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  RETURN QUERY
  WITH session_stats AS (
    SELECT s.user_id,
           COUNT(*)::bigint AS login_count,
           (array_agg(s.ip_address ORDER BY s.logged_in_at DESC))[1] AS last_ip,
           (array_agg(s.user_agent  ORDER BY s.logged_in_at DESC))[1] AS last_ua
    FROM app_sessions s GROUP BY s.user_id
  )
  SELECT
    u.id, u.email::text,
    COALESCE(up.full_name, u.raw_user_meta_data->>'full_name')::text,
    up.nickname::text,
    u.last_sign_in_at, u.created_at,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('role', ar.role, 'tournament_quota', ar.tournament_quota,
              'facility_id', ar.facility_id, 'granted_at', ar.granted_at, 'notes', ar.notes) ORDER BY ar.granted_at)
              FROM app_roles ar WHERE ar.user_id = u.id), '[]'::jsonb),
    (SELECT COUNT(*) FROM tournaments t WHERE t.created_by = u.id)::bigint,
    COALESCE(ss.login_count, 0)::bigint,
    ss.last_ip::text, ss.last_ua::text,
    up.deactivated_at,
    EXISTS (SELECT 1 FROM email_suppression es WHERE es.email = lower(u.email))
  FROM auth.users u
  LEFT JOIN user_profiles up ON up.user_id = u.id
  LEFT JOIN session_stats ss ON ss.user_id = u.id
  WHERE p_search IS NULL
     OR u.email ILIKE '%'||p_search||'%'
     OR up.nickname ILIKE '%'||p_search||'%'
     OR up.full_name ILIKE '%'||p_search||'%'
     OR (u.raw_user_meta_data->>'full_name') ILIKE '%'||p_search||'%'
  ORDER BY u.created_at DESC
  LIMIT 100;
END;
$$;
GRANT EXECUTE ON FUNCTION get_all_users(text) TO authenticated;
