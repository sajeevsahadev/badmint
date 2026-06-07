-- Fix: register_for_tournament had registered_by and notes swapped in VALUES clause
-- registered_by (uuid) was receiving p_notes (text) and vice versa
-- Run this once in Supabase SQL Editor

CREATE OR REPLACE FUNCTION register_for_tournament(
  p_tournament_id uuid,
  p_team_name     text,
  p_player_a_name text,
  p_player_b_name text DEFAULT NULL,
  p_notes         text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tour record;
  v_count int;
  v_id    uuid;
BEGIN
  SELECT * INTO v_tour FROM tournaments WHERE id = p_tournament_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF v_tour.status <> 'registration_open' THEN
    RAISE EXCEPTION 'Registration is not open for this tournament';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM tournament_registrations
  WHERE tournament_id = p_tournament_id AND status IN ('pending','confirmed');
  IF v_count >= v_tour.max_teams THEN
    RAISE EXCEPTION 'Tournament is full (% teams)', v_tour.max_teams;
  END IF;

  INSERT INTO tournament_registrations (
    tournament_id, team_name, player_a_name, player_b_name,
    registered_by, notes
  ) VALUES (
    p_tournament_id, trim(p_team_name), trim(p_player_a_name),
    NULLIF(trim(p_player_b_name),''), auth.uid(), p_notes
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION register_for_tournament(uuid,text,text,text,text) TO authenticated;
