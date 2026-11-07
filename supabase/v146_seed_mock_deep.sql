-- v146: seed_mock_deep — fabricate a shot-by-shot timeline + coach commentary for a video so the
-- Deep Analysis UI is testable instantly (and as a fallback when the real engine isn't reachable).
-- All rows flagged is_mock. Applied to project bdmiirppiyopmdfrztoz via MCP.
create or replace function public.seed_mock_deep(p_video_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tag uuid; v_dur numeric; i int; v_t numeric; v_type text; v_sev text; v_txt text; v_shot uuid; n int;
  types text[] := array['clear','drop','smash','net','drive','lift'];
begin
  if not public.can_manage_video(p_video_id) then raise exception 'Not allowed'; end if;
  select coalesce(duration_s, 120) into v_dur from public.match_videos where id = p_video_id;

  delete from public.analysis_commentary where video_id = p_video_id and is_mock;
  delete from public.analysis_shots where video_id = p_video_id and is_mock;

  for v_tag in select id from public.video_player_tags where video_id = p_video_id and is_subject loop
    n := 10 + floor(random()*8);
    for i in 1..n loop
      v_t := round((v_dur * i / (n + 1))::numeric, 1);
      v_type := types[1 + floor(random()*array_length(types,1))];
      v_sev := (array['good','info','watch','warning'])[1 + floor(random()*4)];
      insert into public.analysis_shots (video_id, tag_id, idx, t_s, shot_type, confidence, technique, is_mock)
        values (p_video_id, v_tag, i, v_t, v_type, round((0.3+random()*0.3)::numeric,2),
                jsonb_build_object('contact', (array['overhead','mid','low'])[1+floor(random()*3)],
                                   'elbow_up', (random()>0.5), 'recovered', (random()>0.5)),
                true)
        returning id into v_shot;
      v_txt := case v_type
        when 'smash' then 'Big smash here — good steepness, but you landed flat-footed; split-step as you land to recover faster.'
        when 'clear' then 'Clear to the back — solid depth, though your elbow dropped at contact; lift it and take the shuttle in front.'
        when 'drop' then 'Nice disguised drop, but it sat up a touch; brush the shuttle softer and tighter to the net.'
        when 'net'  then 'Net shot — contact was a little low and late; meet it higher and earlier to keep it tight.'
        when 'drive' then 'Flat drive — good pace, but you didn''t cover the straight reply; push back to base after hitting.'
        else 'Lift from the net — it was a bit short and central, an easy smash for the opponent; push it deeper to a corner.' end;
      insert into public.analysis_commentary (video_id, tag_id, shot_id, t_s, lens, text, severity, is_mock)
        values (p_video_id, v_tag, v_shot, v_t, 'coach', v_txt, v_sev, true);
    end loop;
  end loop;

  update public.match_videos set deep_status = 'done', is_deep_mock = true, deep_error = null where id = p_video_id;
end;
$$;
grant execute on function public.seed_mock_deep(uuid) to authenticated;
