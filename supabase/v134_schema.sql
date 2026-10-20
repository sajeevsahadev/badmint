-- =====================================================================
-- Badminton 360 v134 — Daily match digest (replaces per-match email)
-- Applied to prod via Supabase MCP; archived for rebuild parity.
--
-- Per-club summary of a day's matches + the recipients who should get the digest
-- (club member, email_prefs.match_digest on, not deactivated, not suppressed).
-- Consumed by the send-match-digest Edge Function (daily 08:00 UTC = 12:00 Dubai,
-- cron job "daily-match-digest"). The old per-match email (send-match-email) +
-- its email_prefs.match_recorded toggle were removed in favour of this.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.get_today_match_digests(p_day date)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH day_clubs AS (SELECT DISTINCT m.club_id FROM matches m WHERE m.played_on = p_day)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'club_id',   dc.club_id,
    'club_name', c.name,
    'matches', (
      SELECT jsonb_agg(jsonb_build_object(
        'display_name', m.display_name,
        'sides', (SELECT jsonb_agg(jsonb_build_object(
            'side', ms.side, 'score', ms.score, 'is_winner', ms.is_winner,
            'players', (SELECT jsonb_agg(COALESCE(up.nickname, p.display_name) ORDER BY p.display_name)
                        FROM match_participants mp
                        JOIN players p ON p.id = mp.player_id
                        LEFT JOIN user_profiles up ON up.user_id = p.user_id
                        WHERE mp.match_side_id = ms.id)
          ) ORDER BY ms.side)
          FROM match_sides ms WHERE ms.match_id = m.id)
      ) ORDER BY m.created_at)
      FROM matches m WHERE m.club_id = dc.club_id AND m.played_on = p_day),
    'recipients', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'email', u.email,
        'name',  COALESCE(up.nickname, up.full_name, split_part(u.email, '@', 1))))
      FROM club_members cm
      JOIN auth.users u ON u.id = cm.user_id
      LEFT JOIN user_profiles up ON up.user_id = cm.user_id
      WHERE cm.club_id = dc.club_id
        AND u.email IS NOT NULL
        AND up.deactivated_at IS NULL
        AND COALESCE((up.email_prefs->>'match_digest')::boolean, true)
        AND NOT EXISTS (SELECT 1 FROM email_suppression es WHERE es.email = lower(u.email))),
      '[]'::jsonb)
  )), '[]'::jsonb)
  FROM day_clubs dc JOIN clubs c ON c.id = dc.club_id
  WHERE c.deleted_at IS NULL;
$$;
REVOKE ALL ON FUNCTION public.get_today_match_digests(date) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_today_match_digests(date) TO service_role;

-- Cron (run once in SQL editor with pg_cron + pg_net enabled):
-- SELECT cron.schedule('daily-match-digest', '0 8 * * *', $$
--   SELECT net.http_post(
--     url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-match-digest',
--     headers := jsonb_build_object('Content-Type','application/json',
--       'Authorization','Bearer YOUR_PUBLISHABLE_KEY','apikey','YOUR_PUBLISHABLE_KEY'),
--     body := '{}'::jsonb);
-- $$);
