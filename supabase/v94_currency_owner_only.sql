-- v94_currency_owner_only
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Only the club owner (the club admin) may change the currency.
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
  UPDATE clubs SET currency = norm_currency(p_currency) WHERE id = p_club_id;
END;
$function$;;
