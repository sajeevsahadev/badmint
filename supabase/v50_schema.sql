-- =====================================================================
-- Badminton 360 v50 — Consistent leaderboard rank (exclude unplayed members)
-- Run in Supabase SQL Editor (after v49_schema.sql).
--
-- Problem: v_leaderboard.club_rank ranked ALL active players, including
-- brand-new members who have never played (0 games, still at the default
-- Elo 1000). Because 1000 outranks anyone below it, those unplayed members
-- pushed real players down the list — e.g. Sajeev showed Rank #16 on the
-- Profile page but #11 on the Dashboard/Scoreboard, which filter games>0.
-- (Inactive players were already excluded via `WHERE p.is_active = true`;
--  the culprit was UNPLAYED-but-active members, not inactive ones.)
--
-- Fix: club_rank now ranks only players with games > 0. Members who haven't
-- played yet get club_rank = NULL (unranked) instead of a misleading number.
-- Every surface that shows a rank (Dashboard, Scoreboard, ClubProfile,
-- Profile) already filters or now reads this same value, so the rank is
-- identical everywhere. Only the club_rank expression changed; all other
-- columns are byte-for-byte the same.
-- =====================================================================

CREATE OR REPLACE VIEW v_leaderboard AS
 WITH stats AS (
         SELECT p.id,
            p.club_id,
            p.user_id,
            COALESCE(resolve_public_nickname(p.user_id), p.display_name) AS display_name,
            p.elo,
            COALESCE(att.days, 0::bigint) AS days_played,
            COALESCE(w.wins, 0::bigint) AS wins,
            COALESCE(g.games, 0::bigint) AS games,
            COALESCE(cfg.elo_weight, 0.7) AS ew,
            COALESCE(cfg.participation_weight, 0.3) AS pw
           FROM players p
             LEFT JOIN ranking_config cfg ON cfg.club_id = p.club_id
             LEFT JOIN ( SELECT attendance.player_id, count(*) AS days
                   FROM attendance GROUP BY attendance.player_id) att ON att.player_id = p.id
             LEFT JOIN ( SELECT mp.player_id, count(*) AS games
                   FROM match_participants mp GROUP BY mp.player_id) g ON g.player_id = p.id
             LEFT JOIN ( SELECT mp.player_id, count(*) AS wins
                   FROM match_participants mp
                     JOIN match_sides ms ON ms.id = mp.match_side_id AND ms.is_winner
                  GROUP BY mp.player_id) w ON w.player_id = p.id
          WHERE p.is_active = true
        ), bounds AS (
         SELECT stats.club_id,
            min(stats.elo) AS emin, max(stats.elo) AS emax,
            min(stats.days_played) AS dmin, max(stats.days_played) AS dmax
           FROM stats GROUP BY stats.club_id
        )
 SELECT s.id,
    s.club_id,
    s.display_name,
    round(s.elo)::integer AS elo,
    s.days_played,
    s.games,
    s.wins,
        CASE WHEN s.games > 0 THEN round(100.0 * s.wins::numeric / s.games::numeric)
             ELSE 0::numeric END AS win_pct,
    round(100::numeric * CASE WHEN b.emax = b.emin THEN 0.5
             ELSE (s.elo - b.emin) / (b.emax - b.emin) END, 1) AS elo_score,
    round(100::numeric * CASE WHEN b.dmax = b.dmin THEN 0.5
             ELSE (s.days_played - b.dmin)::numeric / (b.dmax - b.dmin)::numeric END, 1) AS part_score,
    round(s.ew * 100::numeric * CASE WHEN b.emax = b.emin THEN 0.5
             ELSE (s.elo - b.emin) / (b.emax - b.emin) END
        + s.pw * 100::numeric * CASE WHEN b.dmax = b.dmin THEN 0.5
             ELSE (s.days_played - b.dmin)::numeric / (b.dmax - b.dmin)::numeric END, 1) AS composite,
    -- Rank only players who have actually played; unplayed members are unranked (NULL).
    CASE WHEN s.games > 0 THEN
      rank() OVER (
        PARTITION BY s.club_id, (s.games > 0)
        ORDER BY (s.ew * CASE WHEN b.emax = b.emin THEN 0.5
                   ELSE (s.elo - b.emin) / (b.emax - b.emin) END
                + s.pw * CASE WHEN b.dmax = b.dmin THEN 0.5
                   ELSE (s.days_played - b.dmin)::numeric / (b.dmax - b.dmin)::numeric END) DESC
      )
    END AS club_rank,
    s.user_id
   FROM stats s
     JOIN bounds b ON b.club_id = s.club_id;
