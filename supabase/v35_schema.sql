-- v35: Push notifications are now global (not scoped to a single club)
-- Makes push_subscriptions.club_id nullable and updates save_push_subscription RPC

-- Step 1: make club_id nullable
ALTER TABLE push_subscriptions ALTER COLUMN club_id DROP NOT NULL;

-- Step 2: new 3-param version (no club_id)
CREATE OR REPLACE FUNCTION save_push_subscription(
  p_endpoint text,
  p_p256dh   text,
  p_auth     text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO push_subscriptions (user_id, club_id, endpoint, p256dh, auth_key)
  VALUES (auth.uid(), NULL, p_endpoint, p_p256dh, p_auth)
  ON CONFLICT (user_id, endpoint)
  DO UPDATE SET p256dh = EXCLUDED.p256dh, auth_key = EXCLUDED.auth_key, club_id = NULL;
END;
$$;
GRANT EXECUTE ON FUNCTION save_push_subscription(text,text,text) TO authenticated;

-- Step 3: backward-compat 4-param overload (accepts club_id but ignores it)
CREATE OR REPLACE FUNCTION save_push_subscription(
  p_club_id  uuid,
  p_endpoint text,
  p_p256dh   text,
  p_auth     text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM save_push_subscription(p_endpoint, p_p256dh, p_auth);
END;
$$;
GRANT EXECUTE ON FUNCTION save_push_subscription(uuid,text,text,text) TO authenticated;
