-- ════════════════════════════════════════════════════════════════════
-- v45_schema.sql — Avatar data layer
-- ════════════════════════════════════════════════════════════════════
-- Adds player user_id to the leaderboard / top-scorer / best-pair views
-- and to get_club_leaderboard so the frontend can batch-fetch avatars
-- (user_profiles.avatar_url) via get_public_profiles(uuid[]).
--
-- Each definition below is based on the LATEST version of that object
-- (v33 for the three views, v20 for get_club_leaderboard) and ONLY adds
-- the user_id column(s). Nickname resolution via resolve_public_nickname()
-- (v33) is preserved exactly — do not regress it.
-- ════════════════════════════════════════════════════════════════════

-- ── v_leaderboard: add p.user_id (from v33) ──────────────────────────
CREATE OR REPLACE VIEW v_leaderboard AS
WITH stats AS (
  SELECT
    p.id, p.club_id, p.user_id,
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
  s.id, s.club_id, s.user_id, s.display_name,
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

-- ── v_best_pairs: add p1_user_id / p2_user_id (from v33) ─────────────
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
  n1.user_id                                                         AS p1_user_id,
  n2.user_id                                                         AS p2_user_id,
  COALESCE(resolve_public_nickname(n1.user_id), n1.display_name) AS p1_name,
  COALESCE(resolve_public_nickname(n2.user_id), n2.display_name) AS p2_name,
  COUNT(*)                                                            AS games,
  SUM(CASE WHEN pr.is_winner THEN 1 ELSE 0 END)                      AS wins,
  ROUND(100.0 * SUM(CASE WHEN pr.is_winner THEN 1 ELSE 0 END) / COUNT(*), 1) AS win_pct
FROM pairs pr
JOIN players n1 ON n1.id = pr.p1
JOIN players n2 ON n2.id = pr.p2
GROUP BY
  pr.club_id, pr.p1, pr.p2, n1.user_id, n2.user_id,
  COALESCE(resolve_public_nickname(n1.user_id), n1.display_name),
  COALESCE(resolve_public_nickname(n2.user_id), n2.display_name)
HAVING COUNT(*) >= 1
ORDER BY win_pct DESC, games DESC;

-- ── v_top_scorers: add p.user_id (from v33) ──────────────────────────
CREATE OR REPLACE VIEW v_top_scorers AS
SELECT
  p.id                                                  AS player_id,
  p.club_id,
  p.user_id,
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

-- ── get_club_leaderboard: add user_id to signature + select (from v20) ──
-- DROP first: changing the RETURNS TABLE column list is not allowed by
-- CREATE OR REPLACE (return type change).
DROP FUNCTION IF EXISTS get_club_leaderboard(uuid);
CREATE OR REPLACE FUNCTION get_club_leaderboard(p_club_id uuid)
RETURNS TABLE (
  id           uuid,
  user_id      uuid,
  display_name text,
  elo          int,
  games        bigint,
  wins         bigint,
  win_pct      numeric,
  days_played  bigint,
  club_rank    bigint
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    vl.id,
    vl.user_id,
    vl.display_name,
    vl.elo,
    vl.games,
    vl.wins,
    vl.win_pct,
    vl.days_played,
    vl.club_rank
  FROM v_leaderboard vl
  WHERE vl.club_id = p_club_id
  ORDER BY vl.club_rank;
END;
$$;
GRANT EXECUTE ON FUNCTION get_club_leaderboard(uuid) TO authenticated, anon;

-- ── get_top_scorers: add user_id to signature + select (from v2) ──
-- Home.vue top-players list reads this; it wraps v_top_scorers (now has
-- user_id). DROP first since the RETURNS TABLE column list changes.
DROP FUNCTION IF EXISTS get_top_scorers(int);
CREATE OR REPLACE FUNCTION get_top_scorers(p_limit int default 50)
RETURNS TABLE(
  player_id uuid, user_id uuid, public_name text, club_name text, emirates text,
  elo int, games int, win_pct numeric, global_rank bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT player_id, user_id, public_name, club_name, emirates, elo, games, win_pct, global_rank
  FROM v_top_scorers ORDER BY global_rank LIMIT p_limit;
$$;
GRANT EXECUTE ON FUNCTION get_top_scorers(int) TO authenticated, anon;
