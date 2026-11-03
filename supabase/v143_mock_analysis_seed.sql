-- v143: mock analysis seeder + rubric matcher.
-- seed_mock_analysis() fabricates plausible tracks/tags/metrics/3-lens reports for a video so the
-- report UI and the chat assistant are fully testable BEFORE the Phase B Modal worker exists.
-- All rows are flagged is_mock = true so real analysis never gets confused with seeded data.
-- match_rubric() is also what the real worker/report layer uses to turn metrics into advice.
-- Applied to project bdmiirppiyopmdfrztoz via MCP.

-- Evaluate the rubric for a lens against a metrics blob -> array of matched findings.
create or replace function public.match_rubric(p_lens text, p_metrics jsonb)
returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'code', code, 'title', title, 'message', message, 'drill', drill,
      'severity', severity, 'metric_key', metric_key,
      'value', (p_metrics->>metric_key)::numeric) order by
      case severity when 'warning' then 0 when 'watch' then 1 else 2 end), '[]'::jsonb)
  from public.analysis_rubric
  where active and lens = p_lens and (p_metrics ? metric_key)
    and case comparator
      when 'lt'      then (p_metrics->>metric_key)::numeric <  threshold
      when 'lte'     then (p_metrics->>metric_key)::numeric <= threshold
      when 'gt'      then (p_metrics->>metric_key)::numeric >  threshold
      when 'gte'     then (p_metrics->>metric_key)::numeric >= threshold
      when 'between' then (p_metrics->>metric_key)::numeric between threshold and threshold2
      else false end;
$$;

create or replace function public.seed_mock_analysis(p_video_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_game text; v_n int; i int; v_track uuid; v_tag uuid;
  v_metrics jsonb; v_cov numeric; v_rec numeric; v_split numeric; v_net numeric;
  v_land numeric; v_lunge numeric; v_back numeric; v_side text; v_has_tags boolean;
  v_coach jsonb; v_well text; v_hold text; v_opp text; v_score int;
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  select coalesce(game_type, 'singles') into v_game from public.match_videos where id = p_video_id;
  v_n := case when v_game = 'doubles' then 4 else 2 end;

  select exists(select 1 from public.video_player_tags where video_id = p_video_id) into v_has_tags;

  -- Refresh mock outputs; keep real (user) tags if they already tagged.
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
    v_cov   := 45 + floor(random()*45);
    v_rec   := round((0.9 + random()*1.2)::numeric, 2);
    v_split := 40 + floor(random()*55);
    v_net   := 30 + floor(random()*60);
    v_land  := 40 + floor(random()*55);
    v_lunge := 30 + floor(random()*60);
    v_back  := 30 + floor(random()*60);
    v_metrics := jsonb_build_object(
      'coverage_pct', v_cov, 'recovery_s', v_rec, 'split_step_pct', v_split,
      'net_win_pct', v_net, 'landing_score', v_land, 'lunge_depth_risk', v_lunge,
      'backcourt_overreach', v_back,
      'shot_mix', jsonb_build_object('clear',30,'drop',22,'smash',18,'net',20,'drive',10));

    insert into public.player_metrics (video_id, tag_id, metrics, confidence, is_mock)
      values (p_video_id, v_tag, v_metrics,
        jsonb_build_object('coverage_pct',0.7,'recovery_s',0.65,'split_step_pct',0.6,
                           'net_win_pct',0.55,'landing_score',0.6,'_note','estimated from mock data'),
        true)
      on conflict (video_id, tag_id) do update
        set metrics = excluded.metrics, confidence = excluded.confidence, is_mock = true;

    v_coach := public.match_rubric('coach', v_metrics);
    v_well  := case when v_cov >= 70 then 'Strong court coverage'
                    when v_net >= 60 then 'Good control at the net'
                    else 'Creating attacking opportunities from the rear court' end;
    v_hold  := coalesce(v_coach->0->>'title', 'Consistency under pressure');
    v_opp   := coalesce(v_coach->0->>'drill', 'Keep recovering to base after every shot to stay in position.');
    v_score := greatest(0, least(100, round(((v_cov + v_split + v_net + v_land + (100 - v_rec*40)) / 5))))::int;

    insert into public.analysis_reports (video_id, tag_id, lens, content, generated_by, is_mock) values
      (p_video_id, v_tag, 'coach',
        jsonb_build_object('summary','Sample coaching analysis (mock data for testing).',
          'well', v_well, 'holding_back', v_hold, 'opportunity', v_opp, 'findings', v_coach),
        'mock', true),
      (p_video_id, v_tag, 'physio',
        jsonb_build_object(
          'disclaimer','Automated movement-safety screen, not a medical diagnosis. See a physiotherapist for pain or injury.',
          'findings', public.match_rubric('physio', v_metrics)),
        'mock', true),
      (p_video_id, v_tag, 'player',
        jsonb_build_object('score', v_score, 'focus', v_hold,
          'highlights', jsonb_build_array(
            'Coverage ' || v_cov || '%', 'Recovery ' || v_rec || 's', 'Split-step ' || v_split || '%')),
        'mock', true)
    on conflict (video_id, tag_id, lens) do update
      set content = excluded.content, is_mock = true;
  end loop;

  update public.match_videos
     set status = 'done', analyzed_at = now(), is_mock = true,
         tag_status = case when v_has_tags then tag_status else 'tagged' end
   where id = p_video_id;
end;
$$;

grant execute on function public.match_rubric(text, jsonb)     to authenticated;
grant execute on function public.seed_mock_analysis(uuid)      to authenticated;
