-- v95_currency_lock_after_data
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Currency is a set-once decision. Changing it only relabels amounts (it does
-- NOT convert them), so once any money is recorded for the club it must lock.
-- The club owner may still correct it while the ledger is completely empty.

-- Has the club recorded any money yet? (expenses, wallet, or opening balances)
CREATE OR REPLACE FUNCTION public.club_has_money(p_club_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM paysplit_expenses         WHERE club_id = p_club_id)
      OR EXISTS (SELECT 1 FROM wallet_contributions      WHERE club_id = p_club_id)
      OR EXISTS (SELECT 1 FROM paysplit_opening_balances WHERE club_id = p_club_id);
$function$;

GRANT EXECUTE ON FUNCTION public.club_has_money(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_club_currency(p_club_id uuid, p_currency text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM club_members
    WHERE club_id = p_club_id AND user_id = auth.uid() AND role = 'owner'
  ) THEN
    RAISE EXCEPTION 'Only the club owner can change the currency';
  END IF;

  IF club_has_money(p_club_id) THEN
    RAISE EXCEPTION 'Currency is locked — money has already been recorded for this club. It can only be set before the first expense.';
  END IF;

  UPDATE clubs SET currency = norm_currency(p_currency) WHERE id = p_club_id;
END;
$function$;;
