-- v144: Phase B report-building + finalizer.
-- build_player_reports() turns stored player_metrics into the 3 lens reports (one source of truth,
-- used by BOTH the mock seeder and the real Modal worker). finalize_analysis() is what the GPU
-- worker calls (service role) after it writes real metrics: build reports + mark the video done.
-- Applied to project bdmiirppiyopmdfrztoz via MCP.

create or replace function public.build_player_reports(p_video_id uuid, p_is_mock boolean)
returns void language plpgsql security definer set search_path = public as $$
declare r record; v_m jsonb; v_coach jsonb; v_well text; v_hold text; v_opp text; v_score int; v_by text;
begin
  v_by := case when p_is_mock then 'mock' else 'engine' end;
  for r in select tag_id, metrics from public.player_metrics where video_id = p_video_id loop
    v_m := r.metrics;
    v_coach := public.match_rubric('coach', v_m);
    v_well := case when coalesce((v_m->>'coverage_pct')::numeric,0) >= 70 then 'Strong court coverage'
                   when coalesce((v_m->>'net_win_pct')::numeric,0)  >= 60 then 'Good control at the net'
                   else 'Creating attacking opportunities from the rear court' end;
    v_hold := coalesce(v_coach->0->>'title', 'Consistency under pressure');
    v_opp  := coalesce(v_coach->0->>'drill', 'Keep recovering to base after every shot to stay in position.');
    v_score := greatest(0, least(100, round((
                 coalesce((v_m->>'coverage_pct')::numeric,50) +
                 coalesce((v_m->>'split_step_pct')::numeric,50) +
                 coalesce((v_m->>'net_win_pct')::numeric,50) +
                 coalesce((v_m->>'landing_score')::numeric,50) +
                 (100 - coalesce((v_m->>'recovery_s')::numeric,1.2) * 40)) / 5)))::int;

    insert into public.analysis_reports (video_id, tag_id, lens, content, generated_by, is_mock) values
      (p_video_id, r.tag_id, 'coach',
        jsonb_build_object(
          'summary', case when p_is_mock then 'Sample coaching analysis (mock data for testing).'
                          else 'Coaching analysis from your match video.' end,
          'well', v_well, 'holding_back', v_hold, 'opportunity', v_opp, 'findings', v_coach),
        v_by, p_is_mock),
      (p_video_id, r.tag_id, 'physio',
        jsonb_build_object(
          'disclaimer','Automated movement-safety screen, not a medical diagnosis. See a physiotherapist for pain or injury.',
          'findings', public.match_rubric('physio', v_m)),
        v_by, p_is_mock),
      (p_video_id, r.tag_id, 'player',
        jsonb_build_object('score', v_score, 'focus', v_hold,
          'highlights', jsonb_build_array(
            'Coverage ' || (v_m->>'coverage_pct') || '%',
            'Recovery ' || (v_m->>'recovery_s') || 's',
            'Split-step ' || (v_m->>'split_step_pct') || '%')),
        v_by, p_is_mock)
    on conflict (video_id, tag_id, lens) do update
      set content = excluded.content, is_mock = excluded.is_mock, generated_by = excluded.generated_by;
  end loop;
end;
$$;

-- Called by the Modal worker (service role) once it has written real player_metrics.
create or replace function public.finalize_analysis(p_video_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.build_player_reports(p_video_id, false);
  update public.match_videos
     set status = 'done', analyzed_at = now(), is_mock = false, error = null
   where id = p_video_id;
end;
$$;

-- Worker marks a failure (so the UI can show it instead of spinning forever).
create or replace function public.fail_analysis(p_video_id uuid, p_error text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.match_videos set status = 'failed', error = left(coalesce(p_error,'analysis failed'), 500)
   where id = p_video_id;
end;
$$;

-- Rewrite the mock seeder to reuse build_player_reports (single source of truth for report shape).
create or replace function public.seed_mock_analysis(p_video_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_game text; v_n int; i int; v_track uuid; v_tag uuid;
  v_metrics jsonb; v_cov numeric; v_rec numeric; v_split numeric; v_net numeric;
  v_land numeric; v_lunge numeric; v_back numeric; v_side text; v_has_tags boolean;
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  select coalesce(game_type, 'singles') into v_game from public.match_videos where id = p_video_id;
  v_n := case when v_game = 'doubles' then 4 else 2 end;
  select exists(select 1 from public.video_player_tags where video_id = p_video_id) into v_has_tags;

  delete from public.analysis_reports r where r.video_id = p_video_id and r.is_mock;
  delete from public.player_metrics  m where m.video_id = p_video_id and m.is_mock;
  if not v_has_tags then
    delete from public.video_player_tags   g where g.video_id = p_video_id;
    delete from public.video_person_tracks t where t.video_id = p_video_id and t.is_mock;
    for i in 1..v_n loop
      v_side := case when v_game = 'doubles'
                     then (array['near_left','near_right','far_left','far_right'])[i]
                     else (array['near','far'])[i] end;
      insert into public.video_person_tracks (video_id, track_label, court_side, confidence, is_mock, first_seen_s, last_seen_s)
        values (p_video_id, 'P'||i, v_side, 0.7, true, 0, 60) returning id into v_track;
      insert into public.video_player_tags (video_id, track_id, label, court_side, is_subject)
        values (p_video_id, v_track, 'Player '||i, v_side, true);
    end loop;
  end if;

  for v_tag in select id from public.video_player_tags where video_id = p_video_id loop
    v_cov := 45 + floor(random()*45); v_rec := round((0.9 + random()*1.2)::numeric, 2);
    v_split := 40 + floor(random()*55); v_net := 30 + floor(random()*60);
    v_land := 40 + floor(random()*55); v_lunge := 30 + floor(random()*60); v_back := 30 + floor(random()*60);
    v_metrics := jsonb_build_object(
      'coverage_pct', v_cov, 'recovery_s', v_rec, 'split_step_pct', v_split,
      'net_win_pct', v_net, 'landing_score', v_land, 'lunge_depth_risk', v_lunge,
      'backcourt_overreach', v_back,
      'shot_mix', jsonb_build_object('clear',30,'drop',22,'smash',18,'net',20,'drive',10));
    insert into public.player_metrics (video_id, tag_id, metrics, confidence, is_mock)
      values (p_video_id, v_tag, v_metrics,
        jsonb_build_object('coverage_pct',0.7,'recovery_s',0.65,'split_step_pct',0.6,
                           'net_win_pct',0.55,'landing_score',0.6,'_note','estimated from mock data'), true)
      on conflict (video_id, tag_id) do update
        set metrics = excluded.metrics, confidence = excluded.confidence, is_mock = true;
  end loop;

  perform public.build_player_reports(p_video_id, true);
  update public.match_videos
     set status = 'done', analyzed_at = now(), is_mock = true,
         tag_status = case when v_has_tags then tag_status else 'tagged' end
   where id = p_video_id;
end;
$$;

grant execute on function public.finalize_analysis(uuid)       to service_role;
grant execute on function public.fail_analysis(uuid, text)     to service_role;
grant execute on function public.build_player_reports(uuid, boolean) to service_role;
