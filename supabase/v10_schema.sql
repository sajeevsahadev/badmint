-- =====================================================================
-- Badmint v10 — Nickname-first display names everywhere
-- Run once in Supabase SQL Editor after v9_schema.sql
-- All three objects use COALESCE(nickname, display_name) so guest
-- players (no linked account) still show their roster name.
-- =====================================================================

-- ── v_leaderboard: add user_profiles join for nickname ──────────────
CREATE OR REPLACE VIEW v_leaderboard AS
WITH stats AS (
  SELECT
    p.id, p.club_id,
    COALESCE(up.nickname, p.display_name) AS display_name,
    p.elo,
    COALESCE(att.days, 0)                   AS days_played,
    COALESCE(w.wins,  0)                    AS wins,
    COALESCE(g.games, 0)                    AS games,
    COALESCE(cfg.elo_weight,          0.7)  AS ew,
    COALESCE(cfg.participation_weight, 0.3) AS pw
  FROM players p
  LEFT JOIN user_profiles up  ON up.user_id  = p.user_id
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


-- ── get_club_players: already JOINs user_profiles — just add COALESCE ──
CREATE OR REPLACE FUNCTION get_club_players(p_club_id uuid)
RETURNS TABLE(
  id            uuid,
  display_name  text,
  elo           numeric,
  is_active     boolean,
  user_id       uuid,
  last_seen_at  timestamptz,
  online_status text
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    p.id,
    COALESCE(up.nickname, p.display_name) AS display_name,
    p.elo, p.is_active, p.user_id,
    up.last_seen_at,
    CASE
      WHEN up.last_seen_at >= now() - interval '10 minutes' THEN 'online'
      WHEN up.last_seen_at >= now() - interval '1 month'    THEN 'recent'
      ELSE                                                        'offline'
    END AS online_status
  FROM players p
  LEFT JOIN user_profiles up ON up.user_id = p.user_id
  WHERE p.club_id = p_club_id
  ORDER BY p.is_active DESC, p.elo DESC;
$$;


-- ── v_best_pairs: add user_profiles joins for both pair members ──────
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
  COALESCE(up1.nickname, n1.display_name) AS p1_name,
  COALESCE(up2.nickname, n2.display_name) AS p2_name,
  COUNT(*)                                                            AS games,
  SUM(CASE WHEN pr.is_winner THEN 1 ELSE 0 END)                      AS wins,
  ROUND(100.0 * SUM(CASE WHEN pr.is_winner THEN 1 ELSE 0 END) / COUNT(*), 1) AS win_pct
FROM pairs pr
JOIN players n1 ON n1.id = pr.p1
JOIN players n2 ON n2.id = pr.p2
LEFT JOIN user_profiles up1 ON up1.user_id = n1.user_id
LEFT JOIN user_profiles up2 ON up2.user_id = n2.user_id
GROUP BY
  pr.club_id, pr.p1, pr.p2,
  COALESCE(up1.nickname, n1.display_name),
  COALESCE(up2.nickname, n2.display_name)
HAVING COUNT(*) >= 1
ORDER BY win_pct DESC, games DESC;
