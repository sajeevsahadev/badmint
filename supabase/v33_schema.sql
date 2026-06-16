-- =====================================================================
-- Badmint v33 — Lock down user_profiles RLS: phone/gender (and full_name)
-- were SELECT-able by ANY authenticated client straight through the
-- Supabase REST API, even though no view in the app shows them to other
-- users. The old policy was `up_read on user_profiles for select using
-- (true)` — wide open. This migration tightens it to owner-only and adds
-- three SECURITY DEFINER RPCs so legitimate cross-user reads keep working
-- through an explicit, audited path instead of an open table policy.
--
-- IMPORTANT: v_leaderboard, v_best_pairs and v_top_scorers currently
-- LEFT JOIN user_profiles directly to resolve nicknames, and several
-- views (Dashboard.vue, Scoreboard.vue, Compare.vue, PlayerProfile.vue)
-- query those views directly via supabase.from(...) — NOT through a
-- SECURITY DEFINER wrapper. Whether a plain view bypasses RLS via its
-- owner's privileges or not is a subtlety this codebase has clearly hit
-- before (see get_club_leaderboard's comment: "SECURITY DEFINER bypasses
-- the v_leaderboard / players RLS"). Rather than gamble on that, this
-- migration redefines those three views to resolve nicknames via a
-- SECURITY DEFINER function call instead of a raw join — that bypass is
-- unambiguous and version-independent, so nicknames keep resolving
-- correctly for every viewer no matter how the view is queried.
--
-- Run once in Supabase SQL Editor, AFTER v32_schema.sql.
-- =====================================================================

-- ── 1. SECURITY DEFINER nickname resolver ────────────────────────────
-- Internal helper used inside the views below. Only ever returns the
-- nickname (already the documented public-safe field), so it's harmless
-- even if called directly — no need to lock down its grants further.
CREATE OR REPLACE FUNCTION resolve_public_nickname(p_user_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT nickname FROM user_profiles WHERE user_id = p_user_id;
$$;

-- ── 2. Public-safe profile lookup ────────────────────────────────────
-- Replaces direct table reads in PlayerProfile.vue and playerNames.js,
-- which read OTHER users' profiles by user_id. Exposes exactly the
-- columns already documented as public: nickname, bio, emirate, avatar_url.
CREATE OR REPLACE FUNCTION get_public_profiles(p_user_ids uuid[])
RETURNS TABLE(user_id uuid, nickname text, bio text, emirate text, avatar_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT user_id, nickname, bio, emirate, avatar_url
  FROM user_profiles
  WHERE user_id = ANY(p_user_ids);
$$;
GRANT EXECUTE ON FUNCTION get_public_profiles(uuid[]) TO authenticated;

-- ── 3. Manager/member-scoped name lookup for Manage.vue ──────────────
-- Manage.vue's member list shows nickname > full_name as a fallback —
-- full_name is more sensitive than nickname (it's the Google account
-- name, not a chosen public handle) so it does NOT belong in the broadly
-- public function above. This preserves today's exact behaviour: any
-- member of a club can see fellow members' names on the Manage page —
-- same blast radius as before, just enforced here instead of via open RLS.
CREATE OR REPLACE FUNCTION get_member_profile_names(p_club_id uuid)
RETURNS TABLE(user_id uuid, nickname text, full_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT up.user_id, up.nickname, up.full_name
  FROM user_profiles up
  JOIN club_members cm ON cm.user_id = up.user_id AND cm.club_id = p_club_id
  WHERE EXISTS (
    SELECT 1 FROM club_members me WHERE me.club_id = p_club_id AND me.user_id = auth.uid()
  );
$$;
GRANT EXECUTE ON FUNCTION get_member_profile_names(uuid) TO authenticated;

-- ── 4. Tighten user_profiles RLS to owner-only SELECT ────────────────
DROP POLICY IF EXISTS up_read ON user_profiles;
CREATE POLICY up_read_own ON user_profiles FOR SELECT USING (user_id = auth.uid());

-- ── 5. Redefine the three views to resolve nicknames via the function
--      above instead of a raw LEFT JOIN to user_profiles. Output column
--      list/order is unchanged from the current definitions (v10/v4), so
--      this is a safe CREATE OR REPLACE VIEW. ─────────────────────────

CREATE OR REPLACE VIEW v_leaderboard AS
WITH stats AS (
  SELECT
    p.id, p.club_id,
    COALESCE(resolve_public_nickname(p.user_id), p.display_name) AS display_name,
    p.elo,
    COALESCE(att.days, 0)                   AS days_played,
    COALESCE(w.wins,  0)                    AS wins,
    COALESCE(g.games, 0)                    AS games,
    COALESCE(cfg.elo_weight,          0.7)  AS ew,
    COALESCE(cfg.participation_weight, 0.3) AS pw
  FROM players p
  LEFT JOIN ranking_config cfg ON cfg.club_id = p.club_id
  LEFT JOIN (
    SELECT player_id, COUNT(*) days FROM attendance GROUP BY player_id
  ) att ON att.player_id = p.id
  LEFT JOIN (
    SELECT mp.player_id, COUNT(*) games
    FROM match_participants mp GROUP BY mp.player_id
  ) g ON g.player_id = p.id
  LEFT JOIN (
    SELECT mp.player_id, COUNT(*) wins
    FROM match_participants mp
    JOIN match_sides ms ON ms.id = mp.match_side_id AND ms.is_winner
    GROUP BY mp.player_id
  ) w ON w.player_id = p.id
  WHERE p.is_active = true
),
bounds AS (
  SELECT club_id,
    MIN(elo) emin, MAX(elo) emax,
    MIN(days_played) dmin, MAX(days_played) dmax
  FROM stats GROUP BY club_id
)
SELECT
  s.id, s.club_id, s.display_name,
  ROUND(s.elo)::int                                          AS elo,
  s.days_played, s.games, s.wins,
  CASE WHEN s.games > 0 THEN ROUND(100.0 * s.wins / s.games) ELSE 0 END AS win_pct,
  ROUND(100 * CASE WHEN b.emax = b.emin THEN 0.5
       ELSE (s.elo - b.emin) / (b.emax - b.emin) END, 1)   AS elo_score,
  ROUND(100 * CASE WHEN b.dmax = b.dmin THEN 0.5
       ELSE (s.days_played - b.dmin)::numeric / (b.dmax - b.dmin) END, 1) AS part_score,
  ROUND(
    s.ew * 100 * CASE WHEN b.emax = b.emin THEN 0.5
         ELSE (s.elo - b.emin) / (b.emax - b.emin) END
  + s.pw * 100 * CASE WHEN b.dmax = b.dmin THEN 0.5
         ELSE (s.days_played - b.dmin)::numeric / (b.dmax - b.dmin) END
  , 1)                                                       AS composite,
  RANK() OVER (
    PARTITION BY s.club_id
    ORDER BY (
      s.ew * CASE WHEN b.emax = b.emin THEN 0.5 ELSE (s.elo - b.emin) / (b.emax - b.emin) END
    + s.pw * CASE WHEN b.dmax = b.dmin THEN 0.5 ELSE (s.days_played - b.dmin)::numeric / (b.dmax - b.dmin) END
    ) DESC
  )                                                          AS club_rank
FROM stats s JOIN bounds b ON b.club_id = s.club_id;

CREATE OR REPLACE VIEW v_best_pairs AS
WITH pair_games AS (
  SELECT
    ms.id AS side_id, ms.match_id, ms.is_winner, mp.player_id, p.club_id
  FROM match_sides ms
  JOIN match_participants mp ON mp.match_side_id = ms.id
  JOIN players p ON p.id = mp.player_id
),
pairs AS (
  SELECT
    a.club_id,
    LEAST(a.player_id, b.player_id)    AS p1,
    GREATEST(a.player_id, b.player_id) AS p2,
    a.is_winner
  FROM pair_games a
  JOIN pair_games b ON a.side_id = b.side_id AND a.player_id < b.player_id
)
SELECT
  pr.club_id, pr.p1, pr.p2,
  COALESCE(resolve_public_nickname(n1.user_id), n1.display_name) AS p1_name,
  COALESCE(resolve_public_nickname(n2.user_id), n2.display_name) AS p2_name,
  COUNT(*)                                                            AS games,
  SUM(CASE WHEN pr.is_winner THEN 1 ELSE 0 END)                      AS wins,
  ROUND(100.0 * SUM(CASE WHEN pr.is_winner THEN 1 ELSE 0 END) / COUNT(*), 1) AS win_pct
FROM pairs pr
JOIN players n1 ON n1.id = pr.p1
JOIN players n2 ON n2.id = pr.p2
GROUP BY
  pr.club_id, pr.p1, pr.p2,
  COALESCE(resolve_public_nickname(n1.user_id), n1.display_name),
  COALESCE(resolve_public_nickname(n2.user_id), n2.display_name)
HAVING COUNT(*) >= 1
ORDER BY win_pct DESC, games DESC;

CREATE OR REPLACE VIEW v_top_scorers AS
SELECT
  p.id                                                  AS player_id,
  p.club_id,
  c.name                                                AS club_name,
  c.emirates,
  COALESCE(resolve_public_nickname(p.user_id), p.display_name) AS public_name,
  ROUND(p.elo)::int                                     AS elo,
  COALESCE(vl.games, 0)                                 AS games,
  COALESCE(vl.wins, 0)                                  AS wins,
  COALESCE(vl.win_pct, 0)                               AS win_pct,
  COALESCE(vl.days_played, 0)                           AS days_played,
  RANK() OVER (ORDER BY p.elo DESC)                     AS global_rank
FROM players p
JOIN clubs c ON c.id = p.club_id
LEFT JOIN v_leaderboard vl ON vl.id = p.id
WHERE p.is_active = true AND COALESCE(vl.games, 0) >= 1;
