-- v116_admin_add_team
-- Let a tournament director add a team directly (walk-ins, phone/WhatsApp
-- sign-ups, or entering the whole field manually). Complements player
-- self-registration on the public page.
CREATE OR REPLACE FUNCTION public.admin_add_team(
  p_tournament_id uuid, p_team_name text, p_player_a_name text,
  p_player_b_name text DEFAULT NULL, p_contact_phone text DEFAULT NULL,
  p_confirmed boolean DEFAULT true)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_max int; v_confirmed int; v_status text; v_pay text; v_id uuid;
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF COALESCE(trim(p_team_name),'') = '' OR COALESCE(trim(p_player_a_name),'') = '' THEN
    RAISE EXCEPTION 'Team name and player 1 are required'; END IF;
  IF EXISTS (SELECT 1 FROM tournament_registrations
             WHERE tournament_id = p_tournament_id AND lower(team_name) = lower(trim(p_team_name))
               AND status <> 'rejected') THEN
    RAISE EXCEPTION 'A team named "%" already exists in this tournament', trim(p_team_name); END IF;

  SELECT max_teams INTO v_max FROM tournaments WHERE id = p_tournament_id;
  SELECT COUNT(*) INTO v_confirmed FROM tournament_registrations
   WHERE tournament_id = p_tournament_id AND status = 'confirmed';

  IF p_confirmed AND v_confirmed < v_max THEN v_status := 'confirmed';
  ELSIF p_confirmed                        THEN v_status := 'waitlisted';
  ELSE                                          v_status := 'pending';
  END IF;
  v_pay := CASE WHEN v_status = 'confirmed' THEN 'confirmed' ELSE 'pending' END;

  INSERT INTO tournament_registrations
    (tournament_id, team_name, player_a_name, player_b_name, registered_by, contact_phone, status, payment_status)
  VALUES (p_tournament_id, trim(p_team_name), trim(p_player_a_name),
          NULLIF(trim(p_player_b_name),''), NULL, NULLIF(trim(p_contact_phone),''), v_status, v_pay)
  RETURNING id INTO v_id;
  RETURN v_id;
END;$$;
GRANT EXECUTE ON FUNCTION public.admin_add_team(uuid,text,text,text,text,boolean) TO authenticated;
