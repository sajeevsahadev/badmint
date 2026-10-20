-- =====================================================================
-- Badminton 360 v133 — Super admin can DO everything in any club
-- Applied to prod via Supabase MCP (3 parts); full bodies in migration history.
--
-- The user (super admin) must act in any club, not just monitor read-only
-- (v130/v131 kept writes gated). Approach:
--   1. Make is_member(c)/is_manager(c) admin-aware → unlocks every RLS write
--      policy (players, matches, attendance, ranking_config, club_schedule) and
--      every RPC that uses those helpers (set_club_country, update/delete/rename
--      match, approve/reject join, toggle_player_active, invite_member, …).
--   2. Patch the write RPCs that use their OWN inline club_members guard: add
--      "AND NOT is_app_admin()" to the guard so an app_admin bypasses it.
-- =====================================================================

-- 1) Admin-aware helpers
CREATE OR REPLACE FUNCTION public.is_member(c uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  select exists(select 1 from club_members where club_id=c and user_id=auth.uid()) or public.is_app_admin();
$$;

CREATE OR REPLACE FUNCTION public.is_manager(c uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  select exists(select 1 from club_members where club_id=c and user_id=auth.uid() and role in ('owner','manager')) or public.is_app_admin();
$$;

-- 2) Inline-guarded write RPCs patched with "AND NOT is_app_admin()" on their guard
--    (full CREATE OR REPLACE bodies are recorded in the Supabase migration history,
--    migrations v133_super_admin_full_access_part1/2/3). Functions patched:
--      Part 1: invite_guest_player, link_guest_player, post_club_message,
--              set_club_currency, set_club_join_policy, update_club_logo, create_schedule
--      Part 2: add_expense (both overloads), add_settlement, add_wallet_contribution,
--              set_opening_balance, delete_opening_balance, create_tournament
--      Part 3: record_match
--    Each guard changed from:  IF NOT EXISTS (SELECT 1 FROM club_members WHERE
--      club_id=p_club_id AND user_id=auth.uid() [AND role IN (...)]) THEN RAISE …
--    to:  IF NOT EXISTS (…) AND NOT is_app_admin() THEN RAISE …
--
-- Not patched (niche real-time, rarely admin-driven for another club):
--   start_live_match(_v2), suggest_lineup(_by_date), update_rotation_stats.
