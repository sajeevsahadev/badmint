-- =====================================================================
-- v129 E2E: "deactivated OR deleted (or unsubscribed) => NO automated email"
-- Run read-only-safe: the single DO block creates a throwaway user, asserts
-- every gate, then RAISEs at the end — which rolls the whole thing back, so
-- nothing persists. A 'PASS:' message = success; any 'FAIL ' = that assertion.
--
--   psql:  \i supabase/test_v129_email_gating.sql
--   MCP :  execute_sql (the exception auto-rolls-back the implicit txn)
-- =====================================================================
DO $$
DECLARE v_uid uuid;
BEGIN
  -- throwaway no-club user, signed up 5 days ago (eligible for the day2 nudge)
  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at, email_confirmed_at)
  VALUES ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
          'zz-gate-test@example.invalid', '', now() - interval '5 days', now(), now())
  RETURNING id INTO v_uid;
  INSERT INTO user_profiles(user_id) VALUES (v_uid);   -- defaults: news=true, deactivated_at=null, country='UAE'

  -- A. BASELINE: active, subscribed, no club => eligible everywhere
  IF NOT EXISTS (SELECT 1 FROM get_pending_nudges() WHERE user_id = v_uid) THEN RAISE EXCEPTION 'FAIL A1: baseline user not in nudges'; END IF;
  IF NOT can_email_user(v_uid, 'news')          THEN RAISE EXCEPTION 'FAIL A2: baseline can_email_user=false'; END IF;
  IF NOT can_email_user(v_uid, 'weekly_digest') THEN RAISE EXCEPTION 'FAIL A3: baseline digest can_email_user=false'; END IF;

  -- B. DEACTIVATE => excluded everywhere, even though prefs stay ON
  UPDATE user_profiles SET deactivated_at = now() WHERE user_id = v_uid;
  IF EXISTS (SELECT 1 FROM get_pending_nudges() WHERE user_id = v_uid) THEN RAISE EXCEPTION 'FAIL B1: deactivated user still in nudges'; END IF;
  IF can_email_user(v_uid, 'news')          THEN RAISE EXCEPTION 'FAIL B2: deactivated can_email_user(news)=true'; END IF;
  IF can_email_user(v_uid, 'weekly_digest') THEN RAISE EXCEPTION 'FAIL B3: deactivated can_email_user(digest)=true'; END IF;
  IF can_email_user(v_uid, NULL)            THEN RAISE EXCEPTION 'FAIL B4: deactivated can_email_user(no-pref)=true'; END IF;

  -- C. REACTIVATE => eligible again
  UPDATE user_profiles SET deactivated_at = NULL WHERE user_id = v_uid;
  IF NOT EXISTS (SELECT 1 FROM get_pending_nudges() WHERE user_id = v_uid) THEN RAISE EXCEPTION 'FAIL C1: reactivated not back in nudges'; END IF;
  IF NOT can_email_user(v_uid, 'news') THEN RAISE EXCEPTION 'FAIL C2: reactivated can_email_user=false'; END IF;

  -- D. UNSUBSCRIBE (suppress email) => excluded, case-insensitive
  PERFORM suppress_email('zz-gate-test@example.invalid', 'test', 'e2e');
  IF EXISTS (SELECT 1 FROM get_pending_nudges() WHERE user_id = v_uid) THEN RAISE EXCEPTION 'FAIL D1: suppressed still in nudges'; END IF;
  IF can_email_user(v_uid, 'news') THEN RAISE EXCEPTION 'FAIL D2: suppressed can_email_user=true'; END IF;
  IF NOT is_email_suppressed('ZZ-Gate-Test@EXAMPLE.invalid') THEN RAISE EXCEPTION 'FAIL D3: suppression not case-insensitive'; END IF;

  -- E. RE-SUBSCRIBE => eligible again
  DELETE FROM email_suppression WHERE email = 'zz-gate-test@example.invalid';
  IF NOT can_email_user(v_uid, 'news') THEN RAISE EXCEPTION 'FAIL E1: after re-subscribe can_email_user=false'; END IF;

  -- F. PREFERENCE OFF => excluded from that category only
  UPDATE user_profiles SET email_prefs = jsonb_build_object('news', false) WHERE user_id = v_uid;
  IF EXISTS (SELECT 1 FROM get_pending_nudges() WHERE user_id = v_uid) THEN RAISE EXCEPTION 'FAIL F1: news=false still in day2/monthly nudges'; END IF;
  IF can_email_user(v_uid, 'news') THEN RAISE EXCEPTION 'FAIL F2: news=false can_email_user(news)=true'; END IF;
  IF NOT can_email_user(v_uid, 'match_recorded') THEN RAISE EXCEPTION 'FAIL F3: news=false wrongly blocked a different category'; END IF;
  UPDATE user_profiles SET email_prefs = jsonb_build_object('news', true) WHERE user_id = v_uid;

  -- G. DELETE (full erasure + auth row removal) => gone everywhere
  PERFORM _erase_user(v_uid);
  DELETE FROM auth.users WHERE id = v_uid;
  IF EXISTS (SELECT 1 FROM get_pending_nudges() WHERE user_id = v_uid) THEN RAISE EXCEPTION 'FAIL G1: deleted user still in nudges'; END IF;
  IF can_email_user(v_uid, 'news') THEN RAISE EXCEPTION 'FAIL G2: deleted can_email_user=true'; END IF;
  IF EXISTS (SELECT 1 FROM user_profiles WHERE user_id = v_uid) THEN RAISE EXCEPTION 'FAIL G3: profile row survived erasure'; END IF;

  -- Success (this RAISE rolls the whole test back, so the throwaway user never persists)
  RAISE EXCEPTION 'PASS: all v129 email-gate assertions passed (A-G)';
END $$;
