-- v117_registration_email_edit_and_status
-- Capture a contact email, let the director edit a team after it's registered
-- and move it between stages, and enforce email+phone for public sign-ups
-- (admin-added teams only need a name).
ALTER TABLE public.tournament_registrations ADD COLUMN IF NOT EXISTS contact_email text;

-- register_for_tournament: add p_contact_email (public form makes email+phone required).
DROP FUNCTION IF EXISTS public.register_for_tournament(uuid, text, text, text, text, text);
CREATE OR REPLACE FUNCTION public.register_for_tournament(
  p_tournament_id uuid, p_team_name text, p_player_a_name text,
  p_player_b_name text DEFAULT NULL, p_notes text DEFAULT NULL,
  p_contact_phone text DEFAULT NULL, p_contact_email text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_tour record; v_count int; v_id uuid; v_status text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required to register'; END IF;
  SELECT * INTO v_tour FROM tournaments WHERE id=p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF v_tour.status <> 'registration_open' THEN RAISE EXCEPTION 'Registration is not open for this tournament'; END IF;
  IF COALESCE(trim(p_contact_email),'') = '' OR COALESCE(trim(p_contact_phone),'') = '' THEN
    RAISE EXCEPTION 'Email and phone are required'; END IF;
  IF EXISTS (SELECT 1 FROM tournament_registrations
             WHERE tournament_id=p_tournament_id AND registered_by=auth.uid()
               AND status NOT IN ('rejected','withdrawn'))
  THEN RAISE EXCEPTION 'You have already registered a team for this tournament'; END IF;
  SELECT COUNT(*) INTO v_count FROM tournament_registrations
   WHERE tournament_id=p_tournament_id AND status IN ('pending','confirmed');
  v_status := CASE WHEN v_count >= v_tour.max_teams THEN 'waitlisted' ELSE 'pending' END;
  INSERT INTO tournament_registrations
    (tournament_id,team_name,player_a_name,player_b_name,registered_by,notes,contact_phone,contact_email,player_a_user_id,status,payment_status)
  VALUES (p_tournament_id,trim(p_team_name),trim(p_player_a_name),NULLIF(trim(p_player_b_name),''),
          auth.uid(),p_notes,trim(p_contact_phone),trim(p_contact_email),auth.uid(),v_status,'pending')
  RETURNING id INTO v_id;
  RETURN v_id;
END;$$;
GRANT EXECUTE ON FUNCTION public.register_for_tournament(uuid,text,text,text,text,text,text) TO authenticated;

-- admin_add_team: add optional email (only name stays mandatory).
DROP FUNCTION IF EXISTS public.admin_add_team(uuid, text, text, text, text, boolean);
CREATE OR REPLACE FUNCTION public.admin_add_team(
  p_tournament_id uuid, p_team_name text, p_player_a_name text,
  p_player_b_name text DEFAULT NULL, p_contact_phone text DEFAULT NULL,
  p_contact_email text DEFAULT NULL, p_confirmed boolean DEFAULT true)
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
    (tournament_id, team_name, player_a_name, player_b_name, registered_by, contact_phone, contact_email, status, payment_status)
  VALUES (p_tournament_id, trim(p_team_name), trim(p_player_a_name),
          NULLIF(trim(p_player_b_name),''), NULL, NULLIF(trim(p_contact_phone),''),
          NULLIF(trim(p_contact_email),''), v_status, v_pay)
  RETURNING id INTO v_id;
  RETURN v_id;
END;$$;
GRANT EXECUTE ON FUNCTION public.admin_add_team(uuid,text,text,text,text,text,boolean) TO authenticated;

-- admin_update_team: edit a team after it's registered (add player names, fix contact).
CREATE OR REPLACE FUNCTION public.admin_update_team(
  p_reg_id uuid, p_team_name text DEFAULT NULL, p_player_a_name text DEFAULT NULL,
  p_player_b_name text DEFAULT NULL, p_contact_phone text DEFAULT NULL, p_contact_email text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_tid uuid;
BEGIN
  SELECT tournament_id INTO v_tid FROM tournament_registrations WHERE id = p_reg_id;
  IF v_tid IS NULL THEN RAISE EXCEPTION 'Registration not found'; END IF;
  IF NOT _can_manage_tournament(v_tid) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_team_name IS NOT NULL AND trim(p_team_name) <> '' AND EXISTS (
      SELECT 1 FROM tournament_registrations
       WHERE tournament_id = v_tid AND id <> p_reg_id
         AND lower(team_name) = lower(trim(p_team_name)) AND status <> 'rejected')
  THEN RAISE EXCEPTION 'A team named "%" already exists', trim(p_team_name); END IF;
  UPDATE tournament_registrations SET
    team_name     = COALESCE(NULLIF(trim(p_team_name),''), team_name),
    player_a_name = COALESCE(NULLIF(trim(p_player_a_name),''), player_a_name),
    player_b_name = CASE WHEN p_player_b_name IS NULL THEN player_b_name ELSE NULLIF(trim(p_player_b_name),'') END,
    contact_phone = CASE WHEN p_contact_phone IS NULL THEN contact_phone ELSE NULLIF(trim(p_contact_phone),'') END,
    contact_email = CASE WHEN p_contact_email IS NULL THEN contact_email ELSE NULLIF(trim(p_contact_email),'') END
  WHERE id = p_reg_id;
END;$$;
GRANT EXECUTE ON FUNCTION public.admin_update_team(uuid,text,text,text,text,text) TO authenticated;

-- set_registration_status: allow 'waitlisted' too, so the director can move a
-- team to any earlier/later stage (e.g. un-approve confirmed -> pending).
CREATE OR REPLACE FUNCTION public.set_registration_status(p_reg_id uuid, p_status text, p_paid boolean DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_tid uuid; v_max int; v_confirmed int;
BEGIN
  SELECT tournament_id INTO v_tid FROM tournament_registrations WHERE id=p_reg_id;
  IF v_tid IS NULL THEN RAISE EXCEPTION 'Registration not found'; END IF;
  IF NOT _can_manage_tournament(v_tid) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_status NOT IN ('pending','confirmed','waitlisted','rejected') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF p_status = 'confirmed' THEN
    SELECT max_teams INTO v_max FROM tournaments WHERE id = v_tid;
    SELECT COUNT(*) INTO v_confirmed FROM tournament_registrations
     WHERE tournament_id = v_tid AND status = 'confirmed' AND id <> p_reg_id;
    IF v_confirmed >= v_max THEN RAISE EXCEPTION 'Tournament is full (% teams)', v_max; END IF;
  END IF;
  UPDATE tournament_registrations SET
    status = p_status,
    payment_status = CASE WHEN p_paid IS NULL THEN payment_status WHEN p_paid THEN 'confirmed' ELSE 'pending' END
  WHERE id=p_reg_id;
END;$$;

-- get_tournament_detail also exposes contact_email to managers (applied in the DB;
-- see the live function definition — body identical to v114 plus the contact_email field).
