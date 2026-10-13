-- =====================================================================
-- Badminton 360 v131 — Super User mode fix: admin read bypass on club RPCs
-- Applied to prod via Supabase MCP; archived here for rebuild parity.
--
-- v130 opened the RLS-bound TABLES to app_admins, but the main screens read
-- through SECURITY DEFINER RPCs that each carry their OWN inline membership
-- guard (SELECT 1 FROM club_members WHERE ... = auth.uid()). For a club the
-- admin isn't a member of, those RPCs returned NULL/empty/raised — so in Super
-- User mode PaySplits (wallet/balance/expenses/settlements/opening), Matches,
-- Schedule and member names showed nothing, and PaySplits kept STALE wallet
-- numbers from the previously-viewed club (the reported "same balance" bug).
--
-- Fix: add an is_app_admin() bypass to the guard of every READ RPC below.
-- WRITE/action RPCs (add_expense, record_match, post_club_message, settle, …)
-- are deliberately left member/manager-gated, so monitoring stays read-only.
-- =====================================================================

-- 1. get_wallet_data — RETURN NULL guard
CREATE OR REPLACE FUNCTION public.get_wallet_data(p_club_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid())
     AND NOT public.is_app_admin() THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'contributions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', wc.id, 'player_id', wc.player_id,
        'player_name', COALESCE(up.nickname, p.display_name),
        'amount', wc.amount, 'notes', wc.notes,
        'contributed_at', wc.contributed_at, 'created_by', wc.created_by
      ) ORDER BY wc.contributed_at)
      FROM wallet_contributions wc
      JOIN players p ON p.id = wc.player_id
      LEFT JOIN user_profiles up ON up.user_id = p.user_id
      WHERE wc.club_id = p_club_id), '[]'::jsonb),
    'wallet_expenses', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'title', e.title, 'amount', e.amount,
        'expense_date', e.expense_date, 'created_at', e.created_at
      ) ORDER BY e.expense_date, e.created_at)
      FROM paysplit_expenses e
      WHERE e.club_id = p_club_id AND e.paid_from_wallet = true), '[]'::jsonb),
    'player_balances', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'player_id', b.player_id, 'player_name', b.player_name,
        'contributed', b.contributed, 'expense_share', b.expense_share,
        'balance', b.contributed - b.expense_share
      ) ORDER BY (b.contributed - b.expense_share) DESC)
      FROM (
        SELECT p.id AS player_id, COALESCE(up.nickname, p.display_name) AS player_name,
          COALESCE(c.total, 0) AS contributed, COALESCE(s.total, 0) AS expense_share
        FROM players p
        LEFT JOIN user_profiles up ON up.user_id = p.user_id
        LEFT JOIN (SELECT player_id, SUM(amount) AS total FROM wallet_contributions
                   WHERE club_id = p_club_id GROUP BY player_id) c ON c.player_id = p.id
        LEFT JOIN (SELECT pa.player_id, SUM(pa.share_amount) AS total
                   FROM paysplit_participants pa JOIN paysplit_expenses e ON e.id = pa.expense_id
                   WHERE e.club_id = p_club_id AND e.paid_from_wallet = true GROUP BY pa.player_id) s ON s.player_id = p.id
        WHERE p.club_id = p_club_id AND (c.player_id IS NOT NULL OR s.player_id IS NOT NULL)
      ) b), '[]'::jsonb)
  );
END;
$function$;

-- 2. get_balance_summary — RAISE guard
CREATE OR REPLACE FUNCTION public.get_balance_summary(p_club_id uuid)
RETURNS TABLE(from_player_id uuid, from_name text, to_player_id uuid, to_name text, net_amount numeric)
LANGUAGE plpgsql SECURITY DEFINER AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid())
     AND NOT public.is_app_admin() THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  RETURN QUERY
  WITH raw_debts AS (
    SELECT pp.player_id AS from_id, e.paid_player_id AS to_id, pp.share_amount AS amount
    FROM paysplit_expenses e JOIN paysplit_participants pp ON pp.expense_id = e.id
    WHERE e.club_id = p_club_id AND e.paid_from_wallet = false AND e.paid_player_id IS NOT NULL
      AND pp.player_id <> e.paid_player_id
      AND NOT EXISTS (SELECT 1 FROM paysplit_expense_payers pep WHERE pep.expense_id = e.id)
    UNION ALL
    SELECT pp.player_id AS from_id, pep.player_id AS to_id,
           ROUND((pp.share_amount * pep.amount / e.amount)::numeric, 4) AS amount
    FROM paysplit_expenses e JOIN paysplit_participants pp ON pp.expense_id = e.id
    JOIN paysplit_expense_payers pep ON pep.expense_id = e.id
    WHERE e.club_id = p_club_id AND e.paid_from_wallet = false AND pp.player_id <> pep.player_id
    UNION ALL
    SELECT s.to_player_id AS from_id, s.from_player_id AS to_id, s.amount AS amount
    FROM paysplit_settlements s WHERE s.club_id = p_club_id
  ),
  paired AS (
    SELECT LEAST(from_id, to_id) AS a_id, GREATEST(from_id, to_id) AS b_id,
           SUM(CASE WHEN from_id < to_id THEN amount ELSE -amount END) AS net
    FROM raw_debts GROUP BY LEAST(from_id, to_id), GREATEST(from_id, to_id)
  )
  SELECT
    CASE WHEN p.net > 0 THEN p.a_id ELSE p.b_id END,
    COALESCE(upa.nickname, pa.display_name),
    CASE WHEN p.net > 0 THEN p.b_id ELSE p.a_id END,
    COALESCE(upb.nickname, pb.display_name),
    ABS(p.net)
  FROM paired p
  JOIN players pa ON pa.id = (CASE WHEN p.net > 0 THEN p.a_id ELSE p.b_id END)
  JOIN players pb ON pb.id = (CASE WHEN p.net > 0 THEN p.b_id ELSE p.a_id END)
  LEFT JOIN user_profiles upa ON upa.user_id = pa.user_id
  LEFT JOIN user_profiles upb ON upb.user_id = pb.user_id
  WHERE ABS(p.net) >= 0.01;
END; $function$;

-- 3. get_fifo_result — RETURN NULL guard
CREATE OR REPLACE FUNCTION public.get_fifo_result(p_club_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid())
     AND NOT public.is_app_admin() THEN
    RETURN NULL;
  END IF;

  WITH
  contribs_raw AS (
    SELECT wc.id, wc.player_id, COALESCE(up.nickname, p.display_name) AS player_name,
      wc.amount::numeric AS amount, wc.notes, wc.contributed_at, wc.created_by,
      COALESCE(SUM(wc.amount::numeric) OVER (ORDER BY wc.contributed_at, wc.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS running_before,
      SUM(wc.amount::numeric) OVER (ORDER BY wc.contributed_at, wc.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_through
    FROM wallet_contributions wc
    JOIN players p ON p.id = wc.player_id
    LEFT JOIN user_profiles up ON up.user_id = p.user_id
    WHERE wc.club_id = p_club_id
  ),
  expenses_raw AS (
    SELECT e.id, e.title, e.amount::numeric AS amount, e.expense_date,
      COALESCE(SUM(e.amount::numeric) OVER (ORDER BY e.expense_date, e.created_at, e.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS running_before,
      SUM(e.amount::numeric) OVER (ORDER BY e.expense_date, e.created_at, e.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_through
    FROM paysplit_expenses e
    WHERE e.club_id = p_club_id AND e.paid_from_wallet = true
  ),
  allocations AS (
    SELECT c.id AS contrib_id, e.id AS expense_id, e.title AS expense_title, e.expense_date,
      LEAST(c.running_through, e.running_through) - GREATEST(c.running_before, e.running_before) AS taken
    FROM contribs_raw c
    JOIN expenses_raw e ON c.running_before < e.running_through AND c.running_through > e.running_before
    WHERE LEAST(c.running_through, e.running_through) - GREATEST(c.running_before, e.running_before) > 0.004
  ),
  contrib_summary AS (
    SELECT c.id, c.player_id, c.player_name, c.amount, c.notes, c.contributed_at, c.created_by,
      GREATEST(0, c.amount - COALESCE(SUM(a.taken), 0)) AS remaining,
      COALESCE(jsonb_agg(jsonb_build_object(
        'expenseId', a.expense_id, 'title', a.expense_title,
        'amount', ROUND(a.taken::numeric, 2), 'expense_date', a.expense_date
      ) ORDER BY a.expense_date) FILTER (WHERE a.expense_id IS NOT NULL), '[]'::jsonb) AS consumed_by
    FROM contribs_raw c
    LEFT JOIN allocations a ON a.contrib_id = c.id
    GROUP BY c.id, c.player_id, c.player_name, c.amount, c.notes, c.contributed_at, c.created_by
  )
  SELECT jsonb_build_object(
    'active', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', cs.id, 'player_id', cs.player_id, 'player_name', cs.player_name,
        'amount', cs.amount, 'notes', cs.notes, 'contributed_at', cs.contributed_at,
        'created_by', cs.created_by, 'remaining', ROUND(cs.remaining, 2), 'consumedBy', cs.consumed_by
      ) ORDER BY cs.contributed_at) FROM contrib_summary cs WHERE cs.remaining > 0.005), '[]'::jsonb),
    'consumed', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', cs.id, 'player_id', cs.player_id, 'player_name', cs.player_name,
        'amount', cs.amount, 'notes', cs.notes, 'contributed_at', cs.contributed_at,
        'created_by', cs.created_by, 'remaining', ROUND(cs.remaining, 2), 'consumedBy', cs.consumed_by
      ) ORDER BY cs.contributed_at) FROM contrib_summary cs
        WHERE cs.remaining <= 0.005 AND jsonb_array_length(cs.consumed_by) > 0), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- 4. get_expenses — RAISE guard
CREATE OR REPLACE FUNCTION public.get_expenses(p_club_id uuid)
RETURNS TABLE(id uuid, title text, category text, amount numeric, paid_player_id uuid, paid_name text,
              expense_date date, notes text, paid_from_wallet boolean, created_by uuid,
              created_at timestamp with time zone, participants jsonb, payers jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid())
     AND NOT public.is_app_admin() THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  RETURN QUERY
  SELECT e.id, e.title, e.category, e.amount, e.paid_player_id,
    CASE WHEN e.paid_from_wallet THEN 'Wallet'
         WHEN e.paid_player_id IS NULL THEN 'Multiple payers'
         ELSE COALESCE(up.nickname, pl.display_name) END AS paid_name,
    e.expense_date, e.notes, e.paid_from_wallet, e.created_by, e.created_at,
    COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'player_id', pp.player_id, 'name', COALESCE(up2.nickname, pl2.display_name), 'share', pp.share_amount
      ) ORDER BY COALESCE(up2.nickname, pl2.display_name))
      FROM paysplit_participants pp JOIN players pl2 ON pl2.id = pp.player_id
      LEFT JOIN user_profiles up2 ON up2.user_id = pl2.user_id
      WHERE pp.expense_id = e.id), '[]'::jsonb) AS participants,
    COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'player_id', pep.player_id, 'name', COALESCE(up3.nickname, pl3.display_name), 'amount', pep.amount
      ) ORDER BY COALESCE(up3.nickname, pl3.display_name))
      FROM paysplit_expense_payers pep JOIN players pl3 ON pl3.id = pep.player_id
      LEFT JOIN user_profiles up3 ON up3.user_id = pl3.user_id
      WHERE pep.expense_id = e.id), '[]'::jsonb) AS payers
  FROM paysplit_expenses e
  LEFT JOIN players pl ON pl.id = e.paid_player_id AND pl.club_id = p_club_id
  LEFT JOIN user_profiles up ON up.user_id = pl.user_id
  WHERE e.club_id = p_club_id
  ORDER BY e.expense_date DESC, e.created_at DESC;
END;
$function$;

-- 5. get_settlements — RAISE guard
CREATE OR REPLACE FUNCTION public.get_settlements(p_club_id uuid)
RETURNS TABLE(id uuid, from_player_id uuid, from_name text, to_player_id uuid, to_name text,
              amount numeric, note text, created_at timestamp with time zone, created_by uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid())
     AND NOT public.is_app_admin() THEN
    RAISE EXCEPTION 'Not a member of this club';
  END IF;
  RETURN QUERY
  SELECT s.id, s.from_player_id, COALESCE(upf.nickname, pf.display_name),
         s.to_player_id, COALESCE(upt.nickname, pt.display_name),
         s.amount, s.note, s.created_at, s.created_by
  FROM paysplit_settlements s
  JOIN players pf ON pf.id = s.from_player_id
  JOIN players pt ON pt.id = s.to_player_id
  LEFT JOIN user_profiles upf ON upf.user_id = pf.user_id
  LEFT JOIN user_profiles upt ON upt.user_id = pt.user_id
  WHERE s.club_id = p_club_id
  ORDER BY s.created_at DESC;
END; $function$;

-- 6. get_opening_balances — WHERE EXISTS guard
CREATE OR REPLACE FUNCTION public.get_opening_balances(p_club_id uuid)
RETURNS TABLE(player_id uuid, player_name text, amount numeric, notes text, updated_at timestamp with time zone)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT ob.player_id, COALESCE(up.nickname, p.display_name) AS player_name,
         ob.amount, ob.notes, ob.updated_at
  FROM paysplit_opening_balances ob
  JOIN players p ON p.id = ob.player_id
  LEFT JOIN user_profiles up ON up.user_id = p.user_id
  WHERE ob.club_id = p_club_id
    AND (EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
         OR public.is_app_admin())
  ORDER BY ABS(ob.amount) DESC;
$function$;

-- 7. get_member_profile_names — WHERE EXISTS guard
CREATE OR REPLACE FUNCTION public.get_member_profile_names(p_club_id uuid)
RETURNS TABLE(user_id uuid, nickname text, full_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT up.user_id, up.nickname, up.full_name
  FROM user_profiles up
  JOIN club_members cm ON cm.user_id = up.user_id AND cm.club_id = p_club_id
  WHERE (EXISTS (SELECT 1 FROM club_members me WHERE me.club_id = p_club_id AND me.user_id = auth.uid())
         OR public.is_app_admin());
$function$;

-- 8. get_club_matches — inline EXISTS guard
CREATE OR REPLACE FUNCTION public.get_club_matches(p_club_id uuid, p_limit integer DEFAULT 30,
                                                    p_before timestamp with time zone DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  WITH page AS (
    SELECT m.id, m.played_on, m.created_at, m.created_by, m.display_name, m.match_number
    FROM matches m
    WHERE m.club_id = p_club_id
      AND (p_before IS NULL OR m.created_at < p_before)
      AND (EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = p_club_id AND cm.user_id = auth.uid())
           OR public.is_app_admin())
    ORDER BY m.created_at DESC
    LIMIT greatest(p_limit, 1)
  )
  SELECT jsonb_build_object(
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pg.id, 'played_on', pg.played_on, 'created_at', pg.created_at,
        'created_by', pg.created_by, 'display_name', pg.display_name, 'match_number', pg.match_number,
        'sides', (SELECT jsonb_agg(jsonb_build_object(
            'side', ms.side, 'score', ms.score, 'is_winner', ms.is_winner,
            'players', (SELECT jsonb_agg(jsonb_build_object(
                'id', mp.player_id, 'elo_before', mp.elo_before, 'elo_after', mp.elo_after) ORDER BY mp.id)
              FROM match_participants mp WHERE mp.match_side_id = ms.id)
          ) ORDER BY ms.side)
          FROM match_sides ms WHERE ms.match_id = pg.id)
      ) ORDER BY pg.created_at DESC)
      FROM page pg), '[]'::jsonb),
    'players', COALESCE((
      SELECT jsonb_object_agg(pl.id, jsonb_build_object(
        'name', COALESCE(up.nickname, pl.display_name), 'user_id', pl.user_id, 'avatar', up.avatar_url))
      FROM players pl LEFT JOIN user_profiles up ON up.user_id = pl.user_id
      WHERE pl.id IN (
        SELECT mp.player_id FROM match_participants mp
        JOIN match_sides ms ON ms.id = mp.match_side_id
        WHERE ms.match_id IN (SELECT id FROM page))), '{}'::jsonb)
  );
$function$;

-- 9. get_club_schedule — RAISE guard
CREATE OR REPLACE FUNCTION public.get_club_schedule(p_club_id uuid, p_year integer, p_month integer)
RETURNS TABLE(id uuid, scheduled_date date, facility_id uuid, facility_name text, fac_name text,
              status text, attending_count integer, not_attending_count integer, my_vote text,
              start_time time without time zone, end_time time without time zone, max_attendees integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid())
     AND NOT public.is_app_admin() THEN
    RAISE EXCEPTION 'Not a member';
  END IF;
  RETURN QUERY
  SELECT cs.id, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name AS fac_name, cs.status,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'attending')::int,
    COUNT(sv.id) FILTER (WHERE sv.vote = 'not_attending')::int,
    MAX(sv.vote) FILTER (WHERE sv.user_id = auth.uid()),
    cs.start_time, cs.end_time, cs.max_attendees
  FROM club_schedule cs
  LEFT JOIN facilities f ON f.id = cs.facility_id
  LEFT JOIN schedule_votes sv ON sv.schedule_id = cs.id
  WHERE cs.club_id = p_club_id
    AND EXTRACT(YEAR FROM cs.scheduled_date) = p_year
    AND EXTRACT(MONTH FROM cs.scheduled_date) = p_month
  GROUP BY cs.id, cs.scheduled_date, cs.facility_id, cs.facility_name, f.name, cs.status,
           cs.start_time, cs.end_time, cs.max_attendees
  ORDER BY cs.scheduled_date, cs.start_time NULLS FIRST;
END;
$function$;

-- 10. get_chat_unread_count — CASE WHEN NOT EXISTS guard
CREATE OR REPLACE FUNCTION public.get_chat_unread_count(p_club_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT CASE WHEN NOT EXISTS (
           SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()
         ) AND NOT public.is_app_admin() THEN 0
         ELSE (
           SELECT count(*)::int FROM club_messages m
           WHERE m.club_id = p_club_id AND m.deleted_at IS NULL AND m.user_id <> auth.uid()
             AND m.created_at > COALESCE(
               (SELECT last_read_at FROM club_chat_reads WHERE club_id = p_club_id AND user_id = auth.uid()),
               'epoch'::timestamptz)
         ) END;
$function$;
