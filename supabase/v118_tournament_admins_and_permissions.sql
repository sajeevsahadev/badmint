-- v118_tournament_admins_and_permissions
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- ═══════════════════════════════════════════════════════════════════════
-- v118: Tournament admins as people (assignable by email), create-for-everyone,
-- and super-admin-only delete + rename.
-- ═══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.tournament_admins (
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  added_by      uuid,
  created_at    timestamptz DEFAULT now(),
  PRIMARY KEY (tournament_id, user_id)
);
ALTER TABLE public.tournament_admins ENABLE ROW LEVEL SECURITY;   -- RPC-mediated only
CREATE INDEX IF NOT EXISTS idx_tadmins_user ON public.tournament_admins(user_id);

-- A tournament manager = its creator, a club owner/manager, a tournament admin,
-- an app admin, or a global tournament director.
CREATE OR REPLACE FUNCTION public._can_manage_tournament(p_tournament_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tournaments t
    WHERE t.id = p_tournament_id AND (
      t.created_by = auth.uid()
      OR EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = t.club_id AND cm.user_id = auth.uid() AND cm.role IN ('owner','manager'))
      OR EXISTS (SELECT 1 FROM tournament_admins ta WHERE ta.tournament_id = t.id AND ta.user_id = auth.uid())
      OR is_app_admin()
      OR is_tournament_director()
    )
  );
$$;

-- create_tournament: any club member may create; creator becomes a tournament admin.
CREATE OR REPLACE FUNCTION public.create_tournament(
  p_club_id uuid, p_name text, p_draw_type text DEFAULT 'knockout', p_max_teams integer DEFAULT 16,
  p_description text DEFAULT NULL, p_entry_fee numeric DEFAULT NULL, p_prize_info text DEFAULT NULL,
  p_venue text DEFAULT NULL, p_venue_address text DEFAULT NULL, p_emirate text DEFAULT NULL,
  p_registration_end date DEFAULT NULL, p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL,
  p_courts integer DEFAULT 1, p_is_public boolean DEFAULT true, p_maps_url text DEFAULT NULL,
  p_groups_count integer DEFAULT 0, p_advance_per_group integer DEFAULT 2,
  p_best_of_3 boolean DEFAULT false, p_category text DEFAULT NULL, p_skill_level text DEFAULT NULL,
  p_currency text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid; v_format text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in to create a tournament'; END IF;
  IF NOT EXISTS (SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Join the club first to run a tournament for it'; END IF;
  IF p_draw_type NOT IN ('knockout','round_robin','groups_knockout') THEN RAISE EXCEPTION 'Invalid draw type'; END IF;
  v_format := CASE WHEN p_draw_type='round_robin' THEN 'round_robin' ELSE 'single_elimination' END;
  INSERT INTO tournaments (club_id,name,format,draw_type,max_teams,description,entry_fee,prize_info,
    venue,venue_address,emirate,maps_url,registration_end,start_date,end_date,courts,is_public,
    groups_count,advance_per_group,best_of_3,category,skill_level,currency,created_by)
  VALUES (p_club_id,p_name,v_format,p_draw_type,p_max_teams,p_description,p_entry_fee,p_prize_info,
    p_venue,p_venue_address,p_emirate,p_maps_url,p_registration_end,p_start_date,p_end_date,
    GREATEST(1,COALESCE(p_courts,1)),COALESCE(p_is_public,true),COALESCE(p_groups_count,0),
    COALESCE(p_advance_per_group,2),COALESCE(p_best_of_3,false),
    NULLIF(trim(p_category),''),NULLIF(trim(p_skill_level),''),NULLIF(trim(p_currency),''),auth.uid())
  RETURNING id INTO v_id;
  INSERT INTO tournament_admins (tournament_id, user_id, added_by) VALUES (v_id, auth.uid(), auth.uid())
    ON CONFLICT DO NOTHING;
  RETURN v_id;
END;$$;

-- delete_tournament: super admins only.
CREATE OR REPLACE FUNCTION public.delete_tournament(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT is_app_admin() THEN
    RAISE EXCEPTION 'Only a Badminton 360 admin can delete a tournament';
  END IF;
  DELETE FROM tournaments WHERE id = p_tournament_id;
END;$$;

-- Renaming a tournament is super-admin only (a manager can edit everything else).
CREATE OR REPLACE FUNCTION public.update_tournament_details(
  p_tournament_id uuid, p_name text DEFAULT NULL, p_description text DEFAULT NULL,
  p_entry_fee numeric DEFAULT NULL, p_prize_info text DEFAULT NULL, p_venue text DEFAULT NULL,
  p_venue_address text DEFAULT NULL, p_emirate text DEFAULT NULL, p_registration_end date DEFAULT NULL,
  p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_max_teams integer DEFAULT NULL,
  p_draw_type text DEFAULT NULL, p_courts integer DEFAULT NULL, p_is_public boolean DEFAULT NULL,
  p_maps_url text DEFAULT NULL, p_groups_count integer DEFAULT NULL, p_advance_per_group integer DEFAULT NULL,
  p_best_of_3 boolean DEFAULT NULL, p_category text DEFAULT NULL, p_skill_level text DEFAULT NULL,
  p_currency text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_admin boolean := is_app_admin();
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_name IS NOT NULL AND NOT v_admin THEN
    RAISE EXCEPTION 'Only a Badminton 360 admin can rename a tournament';
  END IF;
  UPDATE tournaments SET
    name=CASE WHEN v_admin THEN COALESCE(p_name,name) ELSE name END,
    description=COALESCE(p_description,description),
    entry_fee=COALESCE(p_entry_fee,entry_fee), prize_info=COALESCE(p_prize_info,prize_info),
    venue=COALESCE(p_venue,venue), venue_address=COALESCE(p_venue_address,venue_address),
    emirate=COALESCE(p_emirate,emirate), registration_end=COALESCE(p_registration_end,registration_end),
    start_date=COALESCE(p_start_date,start_date), end_date=COALESCE(p_end_date,end_date),
    max_teams=COALESCE(p_max_teams,max_teams), draw_type=COALESCE(p_draw_type,draw_type),
    courts=COALESCE(p_courts,courts), is_public=COALESCE(p_is_public,is_public),
    maps_url=COALESCE(p_maps_url,maps_url), groups_count=COALESCE(p_groups_count,groups_count),
    advance_per_group=COALESCE(p_advance_per_group,advance_per_group),
    best_of_3=COALESCE(p_best_of_3,best_of_3),
    category=COALESCE(NULLIF(trim(p_category),''),category),
    skill_level=COALESCE(NULLIF(trim(p_skill_level),''),skill_level),
    currency=COALESCE(NULLIF(trim(p_currency),''),currency),
    updated_at=now()
  WHERE id=p_tournament_id;
END;$$;

-- ── Manage tournament admins (people) ──
CREATE OR REPLACE FUNCTION public.assign_tournament_admin(p_tournament_id uuid, p_email text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_uid uuid; v_email text := lower(trim(p_email));
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT id INTO v_uid FROM auth.users WHERE lower(email) = v_email LIMIT 1;
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No Badminton 360 user found with that email. Ask them to sign in once first.';
  END IF;
  INSERT INTO tournament_admins (tournament_id, user_id, added_by)
  VALUES (p_tournament_id, v_uid, auth.uid()) ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('user_id', v_uid, 'email', v_email);
END;$$;
GRANT EXECUTE ON FUNCTION public.assign_tournament_admin(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_tournament_admin(p_tournament_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF (SELECT created_by FROM tournaments WHERE id = p_tournament_id) = p_user_id THEN
    RAISE EXCEPTION 'The creator stays an admin'; END IF;
  DELETE FROM tournament_admins WHERE tournament_id = p_tournament_id AND user_id = p_user_id;
END;$$;
GRANT EXECUTE ON FUNCTION public.remove_tournament_admin(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_tournament_admins(p_tournament_id uuid)
RETURNS TABLE(user_id uuid, email text, name text, is_creator boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT _can_manage_tournament(p_tournament_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  RETURN QUERY
  SELECT ta.user_id, u.email::text,
         COALESCE(up.nickname, up.full_name, split_part(u.email,'@',1)) AS name,
         (ta.user_id = t.created_by) AS is_creator
  FROM tournament_admins ta
  JOIN tournaments t ON t.id = ta.tournament_id
  JOIN auth.users u ON u.id = ta.user_id
  LEFT JOIN user_profiles up ON up.user_id = ta.user_id
  WHERE ta.tournament_id = p_tournament_id
  ORDER BY is_creator DESC, name;
END;$$;
GRANT EXECUTE ON FUNCTION public.get_tournament_admins(uuid) TO authenticated;

-- Backfill: existing tournament creators become tournament admins.
INSERT INTO public.tournament_admins (tournament_id, user_id, added_by)
SELECT id, created_by, created_by FROM public.tournaments WHERE created_by IS NOT NULL
ON CONFLICT DO NOTHING;;
