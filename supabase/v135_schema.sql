-- =====================================================================
-- Badminton 360 v135 — "New expense" email: participants only, real share
-- Applied to prod via Supabase MCP; archived for rebuild parity.
--
-- Bug: send-expense-email emailed EVERY club member and showed a generic
-- "Your share" = amount / split_count. So someone who wasn't part of the
-- expense (not a participant) got the email with a wrong share.
-- Fix: this RPC returns only the expense's PARTICIPANTS (people the cost is
-- split between) who have a linked account + email + payment_reminders on +
-- not deactivated/suppressed, each with THEIR actual share_amount. The
-- send-expense-email edge fn now takes expense_id and emails only these.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.get_expense_email_recipients(p_expense_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'title',             e.title,
    'amount',            e.amount,
    'currency',          COALESCE(c.currency, 'AED'),
    'club_name',         c.name,
    'paid_name', CASE
       WHEN e.paid_from_wallet THEN 'Club Wallet'
       WHEN EXISTS (SELECT 1 FROM paysplit_expense_payers pep WHERE pep.expense_id = e.id) THEN 'Multiple payers'
       ELSE COALESCE(up0.nickname, pl0.display_name, 'Unknown') END,
    'participant_count', (SELECT count(*) FROM paysplit_participants pp WHERE pp.expense_id = e.id),
    'recipients', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'email', u.email,
        'name',  COALESCE(up.nickname, up.full_name, split_part(u.email, '@', 1)),
        'share', pp.share_amount))
      FROM paysplit_participants pp
      JOIN players p ON p.id = pp.player_id
      JOIN auth.users u ON u.id = p.user_id              -- only players with a linked account
      LEFT JOIN user_profiles up ON up.user_id = p.user_id
      WHERE pp.expense_id = e.id
        AND u.email IS NOT NULL
        AND up.deactivated_at IS NULL
        AND COALESCE((up.email_prefs->>'payment_reminders')::boolean, true)
        AND NOT EXISTS (SELECT 1 FROM email_suppression es WHERE es.email = lower(u.email))
    ), '[]'::jsonb)
  )
  FROM paysplit_expenses e
  JOIN clubs c ON c.id = e.club_id
  LEFT JOIN players pl0 ON pl0.id = e.paid_player_id
  LEFT JOIN user_profiles up0 ON up0.user_id = pl0.user_id
  WHERE e.id = p_expense_id;
$$;
REVOKE ALL ON FUNCTION public.get_expense_email_recipients(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_expense_email_recipients(uuid) TO service_role;
