-- v82_raise_club_limit_to_10
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Raise the per-user club cap from 5 to 10 (memberships + pending requests).

CREATE OR REPLACE FUNCTION public.request_join(p_club_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
declare
  v_email  text;
  v_name   text;
  v_total  integer;
  v_policy text;
begin
  SELECT join_policy INTO v_policy FROM clubs WHERE id = p_club_id;
  IF v_policy = 'closed' THEN
    RAISE EXCEPTION 'This club is closed. Ask a manager to send you an invite.';
  END IF;

  select
    (select count(*) from club_members  where user_id = auth.uid()) +
    (select count(*) from join_requests where user_id = auth.uid() and status = 'pending')
  into v_total;

  if v_total >= 10 then
    raise exception 'You have reached the maximum of 10 clubs. Leave a club or revoke a pending request before joining another.';
  end if;

  select
    u.email,
    coalesce(
      u.raw_user_meta_data->>'full_name',
      u.raw_user_meta_data->>'name',
      split_part(u.email, '@', 1)
    )
  into v_email, v_name
  from auth.users u where u.id = auth.uid();

  insert into join_requests(club_id, user_id, user_email, user_name)
    values (p_club_id, auth.uid(), v_email, v_name)
    on conflict (club_id, user_id) do update
      set status = 'pending', created_at = now()
      where join_requests.status = 'rejected';
end;
$$;

CREATE OR REPLACE FUNCTION public.join_club_public(p_club_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_policy text;
  v_total  integer;
  v_name   text;
  v_email  text;
BEGIN
  SELECT join_policy INTO v_policy FROM clubs WHERE id = p_club_id;
  IF v_policy IS NULL THEN RAISE EXCEPTION 'Club not found'; END IF;

  IF EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RETURN p_club_id;
  END IF;

  IF v_policy <> 'public' THEN
    RAISE EXCEPTION 'This club is not open to public join. Ask a manager for an invite.';
  END IF;

  SELECT (SELECT count(*) FROM club_members  WHERE user_id = auth.uid())
       + (SELECT count(*) FROM join_requests WHERE user_id = auth.uid() AND status = 'pending')
    INTO v_total;
  IF v_total >= 10 THEN
    RAISE EXCEPTION 'You have reached the maximum of 10 clubs. Leave a club before joining another.';
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = auth.uid();
  SELECT COALESCE(nickname, full_name) INTO v_name FROM user_profiles WHERE user_id = auth.uid();

  INSERT INTO club_members(club_id, user_id, role)
    VALUES (p_club_id, auth.uid(), 'player')
    ON CONFLICT DO NOTHING;

  IF NOT EXISTS (SELECT 1 FROM players WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    INSERT INTO players(club_id, user_id, display_name)
      VALUES (p_club_id, auth.uid(),
              COALESCE(NULLIF(trim(v_name), ''), split_part(v_email, '@', 1), 'Player'));
  END IF;

  DELETE FROM join_requests WHERE club_id = p_club_id AND user_id = auth.uid();

  RETURN p_club_id;
END;
$$;;
