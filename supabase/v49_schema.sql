-- =====================================================================
-- Badminton 360 v49 — Security hardening (OWASP / Supabase advisor remediation)
-- Run in Supabase SQL Editor (after v48_schema.sql). Already applied to prod.
--
-- Context: full security assessment (OWASP Top 10 + Supabase linter) — see
-- SECURITY.md for the complete findings report. This migration fixes the two
-- database-layer issues found. Frontend (no XSS sinks/secrets), Edge Functions
-- (all verify caller identity), and RLS (enabled on every public table) passed.
--
-- Fix 1 — A05 Security Misconfiguration / CWE-426 search_path injection:
--   Pin search_path = public on every SECURITY DEFINER function that lacked
--   it (13 flagged). A definer-privileged function without a pinned
--   search_path can be tricked into resolving unqualified object names to
--   attacker-controlled objects on the caller's search_path. The dynamic
--   block fixes all missing ones and future-proofs.
--
-- Fix 2 — A01 Broken Access Control / sensitive data exposure to anon:
--   Three RPCs were executable by the anonymous (logged-out) role and
--   returned/mutated user data with no in-body auth.uid() gate:
--     - get_club_players    → leaked auth user_id + last_seen_at (presence)
--                             for every player in every club to anyone
--     - get_public_profiles → nickname/bio/emirate/avatar scrapeable by
--                             fully anonymous callers
--     - accept_invite       → onboarding write; an anon call with a token
--                             could burn/consume the invite
--   All three are only called from auth-required app routes, so restricting
--   to `authenticated` changes no legitimate behavior.
--
-- NOTE (intentionally NOT changed):
--   * SECURITY DEFINER views (v_leaderboard, v_best_pairs, v_top_scorers,
--     v_club_rankings, v_head_to_head, v_tournament_standings) — flagged by
--     the linter but required by design (CLAUDE.md rule 19) to resolve
--     nicknames across the tightened user_profiles RLS. Read-only, no PII
--     beyond public nickname/elo.
--   * Remaining SECURITY DEFINER RPCs granted to anon — each self-protects
--     via is_manager()/is_app_admin()/auth.uid() (anon → NULL → exception).
--     Left as-is; broad REVOKE deferred to avoid breaking public pages.
--   * auth_leaked_password_protection — N/A, this app is Google-OAuth only,
--     no password auth exists.
-- =====================================================================

-- ── Fix 1: pin search_path on all SECURITY DEFINER funcs missing it ──
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND NOT EXISTS (
        SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c
        WHERE c LIKE 'search_path=%'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public', r.sig);
  END LOOP;
END $$;

-- ── Fix 2: restrict anon-exposed data RPCs to authenticated only ─────
REVOKE EXECUTE ON FUNCTION get_club_players(uuid)      FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION get_club_players(uuid)        TO authenticated;

REVOKE EXECUTE ON FUNCTION get_public_profiles(uuid[])  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION get_public_profiles(uuid[])    TO authenticated;

REVOKE EXECUTE ON FUNCTION accept_invite(text)          FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION accept_invite(text)            TO authenticated;
