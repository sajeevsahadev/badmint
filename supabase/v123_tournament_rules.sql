-- v123_tournament_rules
-- Applied migration exported from Supabase (project bdmiirppiyopmdfrztoz), archived for rebuild parity.

-- ═══════════════════════════════════════════════════════════════════════
-- v123: Rules & regulations per tournament. A sensible default (generalised
-- from a standard doubles rule sheet) is applied to new tournaments and
-- backfilled onto existing ones. Editable by managers, read-only for the public.
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS rules text;

CREATE OR REPLACE FUNCTION public._default_tournament_rules()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
SELECT $rules$1. Team Format: Each team consists of 2 players. Player substitution after the tournament begins is not permitted.
2. Dress Code: Both players of a team must wear matching or same-colour sports attire during their matches.
3. Category: The tournament is open only to players eligible for the announced category.
4. Registration Fee: Registration is confirmed only upon successful payment of the entry fee.
5. Reporting Time: Players must report at least 30 minutes before their scheduled match.
6. Late Arrival: A team that fails to report within 10 minutes of being called may forfeit the match.
7. Match Format: Matches follow the scoring format announced by the organizers before the tournament. Each game is played to 21 points.
8. Tournament Format: As announced by the organizers (group stage and/or knock-out).
9. Service & Court: Initial service and court side will be decided by a toss.
10. Fair Play: Players must maintain proper sportsmanship and respect opponents, officials, organizers and spectators.
11. Match Decisions: The umpire / organizing committee's decision will be final regarding match-related disputes.
12. No Outside Interference: Spectators and other players must not interfere with an ongoing match or dispute decisions during play.
13. Equipment: Players must bring their own rackets and non-marking court shoes. Shuttlecocks will be supplied by the organizers.
14. Injury: Reasonable time may be allowed for minor injuries. If a player cannot continue, the organizers / umpire will decide the outcome.
15. Misconduct: Abusive language, racket throwing, fighting, cheating or serious unsportsmanlike conduct may result in a warning, point penalty, or disqualification.
16. Eligibility Verification: Players may be required to provide identification or other information for category / registration verification.
17. Registered Players Only: Only players whose names were submitted during registration will be allowed to participate.
18. Organizer's Authority: The organizing committee reserves the right to change the schedule or arrangements. The committee's decision shall be final in exceptional situations.

Play fair. Respect all. Enjoy the game.$rules$;
$$;

ALTER TABLE public.tournaments ALTER COLUMN rules SET DEFAULT public._default_tournament_rules();
UPDATE public.tournaments SET rules = public._default_tournament_rules() WHERE rules IS NULL;

-- Managers can edit the rules (added to the existing update RPC).
CREATE OR REPLACE FUNCTION public.update_tournament_details(
  p_tournament_id uuid, p_name text DEFAULT NULL, p_description text DEFAULT NULL,
  p_entry_fee numeric DEFAULT NULL, p_prize_info text DEFAULT NULL, p_venue text DEFAULT NULL,
  p_venue_address text DEFAULT NULL, p_emirate text DEFAULT NULL, p_registration_end date DEFAULT NULL,
  p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_max_teams integer DEFAULT NULL,
  p_draw_type text DEFAULT NULL, p_courts integer DEFAULT NULL, p_is_public boolean DEFAULT NULL,
  p_maps_url text DEFAULT NULL, p_groups_count integer DEFAULT NULL, p_advance_per_group integer DEFAULT NULL,
  p_best_of_3 boolean DEFAULT NULL, p_category text DEFAULT NULL, p_skill_level text DEFAULT NULL,
  p_currency text DEFAULT NULL, p_rules text DEFAULT NULL)
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
    rules=COALESCE(p_rules, rules),
    updated_at=now()
  WHERE id=p_tournament_id;
END;$$;

-- Expose rules on the public payload (read-only for the public).
CREATE OR REPLACE FUNCTION public.get_public_tournament(p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v jsonb; v_tid uuid;
BEGIN
  SELECT id INTO v_tid FROM tournaments WHERE slug = p_code OR share_code = p_code OR id::text = p_code LIMIT 1;
  IF v_tid IS NULL THEN RETURN NULL; END IF;
  SELECT jsonb_build_object(
    'tournament', jsonb_build_object(
      'id',t.id,'name',t.name,'slug',t.slug,'club_id',t.club_id,'club_name',c.name,
      'currency',COALESCE(t.currency,c.currency,'AED'),'description',t.description,'rules',t.rules,
      'draw_type',t.draw_type,'status',t.status,'max_teams',t.max_teams,'entry_fee',t.entry_fee,
      'best_of_3',t.best_of_3,'category',t.category,'skill_level',t.skill_level,
      'prize_info',t.prize_info,'venue',t.venue,'venue_address',t.venue_address,'maps_url',t.maps_url,
      'emirate',t.emirate,'registration_end',t.registration_end,'start_date',t.start_date,'end_date',t.end_date,
      'is_public',t.is_public,'share_code',t.share_code,'courts',t.courts,'updated_at',t.updated_at,
      'advance_per_group',t.advance_per_group,
      'winner_registration_id',t.winner_registration_id,'runner_up_registration_id',t.runner_up_registration_id,
      'third_registration_id',t.third_registration_id,
      'winner_team_name',wr.team_name,'runner_up_team_name',rr.team_name,'third_team_name',thr.team_name,
      'cover_photo_url',t.cover_photo_url,'group_photo_url',t.group_photo_url),
    'can_manage', COALESCE(_can_manage_tournament(v_tid), false),
    'my_registration', (
      SELECT jsonb_build_object('id',tr.id,'team_name',tr.team_name,'status',tr.status,'payment_status',tr.payment_status)
      FROM tournament_registrations tr
      WHERE tr.tournament_id=v_tid AND tr.registered_by = auth.uid() AND tr.status <> 'withdrawn'
      ORDER BY tr.created_at LIMIT 1),
    'teams', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'team_name',tr.team_name,
                 'player_a_name',tr.player_a_name,'player_b_name',tr.player_b_name,'seed',tr.seed)
               ORDER BY COALESCE(tr.seed,9999), tr.created_at)
             FROM tournament_registrations tr WHERE tr.tournament_id=v_tid AND tr.status='confirmed'),'[]'),
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'id',tm.id,'round',tm.round,'position',tm.position,
          'team_a_id',tm.team_a_id,'team_a_name',ta.team_name,
          'team_b_id',tm.team_b_id,'team_b_name',tb.team_name,
          'score_a',tm.score_a,'score_b',tm.score_b,'games',tm.games,
          'winner_id',tm.winner_id,'winner_name',tw.team_name,
          'status',tm.status,'next_match_id',tm.next_match_id,'court',tm.court,
          'stage',tm.stage,'group_label',tm.group_label)
        ORDER BY tm.round, tm.position)
      FROM tournament_matches tm
      LEFT JOIN tournament_registrations ta ON ta.id=tm.team_a_id
      LEFT JOIN tournament_registrations tb ON tb.id=tm.team_b_id
      LEFT JOIN tournament_registrations tw ON tw.id=tm.winner_id
      WHERE tm.tournament_id=v_tid), '[]'),
    'standings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'registration_id',vs.registration_id,'team_name',vs.team_name,'seed',vs.seed,
          'wins',vs.wins,'losses',vs.losses,'played',vs.played,'sets_for',vs.sets_for,'sets_against',vs.sets_against)
        ORDER BY vs.wins DESC, (vs.sets_for - vs.sets_against) DESC)
      FROM v_tournament_standings vs WHERE vs.tournament_id=v_tid), '[]'),
    'photos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',tp.id,'url',tp.url,'thumb_url',tp.thumb_url,'caption',tp.caption,'kind',tp.kind)
             ORDER BY tp.created_at)
      FROM tournament_photos tp WHERE tp.tournament_id=v_tid), '[]'),
    'confirmed_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='confirmed'),
    'pending_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='pending'),
    'waitlist_count',(SELECT count(*) FROM tournament_registrations WHERE tournament_id=v_tid AND status='waitlisted')
  ) INTO v
  FROM tournaments t JOIN clubs c ON c.id=t.club_id
  LEFT JOIN tournament_registrations wr  ON wr.id  = t.winner_registration_id
  LEFT JOIN tournament_registrations rr  ON rr.id  = t.runner_up_registration_id
  LEFT JOIN tournament_registrations thr ON thr.id = t.third_registration_id
  WHERE t.id=v_tid;
  RETURN v;
END;$$;;
