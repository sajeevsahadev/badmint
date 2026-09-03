-- v87_share_links
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- Branded short links for shareable player cards: badminton360.app/p/<code>
CREATE TABLE IF NOT EXISTS share_links (
  code text PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE (player_id)
);
ALTER TABLE share_links ENABLE ROW LEVEL SECURITY;  -- access only via the RPCs below

-- One stable short code per player; created on demand at share time.
CREATE OR REPLACE FUNCTION public.get_or_create_player_share_code(p_player_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_code text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id) THEN
    RAISE EXCEPTION 'Player not found';
  END IF;
  SELECT code INTO v_code FROM share_links WHERE player_id = p_player_id;
  IF v_code IS NOT NULL THEN RETURN v_code; END IF;
  LOOP
    v_code := substr(md5(gen_random_uuid()::text), 1, 7);   -- 7 hex chars
    BEGIN
      INSERT INTO share_links(code, player_id) VALUES (v_code, p_player_id);
      RETURN v_code;
    EXCEPTION
      WHEN unique_violation THEN
        -- player got a code concurrently → return that one
        SELECT code INTO v_code FROM share_links WHERE player_id = p_player_id;
        IF v_code IS NOT NULL THEN RETURN v_code; END IF;
        -- else code collision → loop and retry with a new code
    END;
  END LOOP;
END; $$;

-- Public resolver used by the /p/:code redirect (callable by anon).
CREATE OR REPLACE FUNCTION public.resolve_share_code(p_code text)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE SET search_path TO 'public' AS $$
  SELECT player_id FROM share_links WHERE code = p_code;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_player_share_code(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_share_code(text) TO anon, authenticated;;
