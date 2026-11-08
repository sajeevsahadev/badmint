-- v150: Physio findings rewritten in simple everyday English (applied via MCP 2026-11-08).
-- Existing analysis_reports physio findings were refreshed from the rubric at the same time.
update public.analysis_rubric set title='Landing after jumps',
 message='When you land after a jump, your knees bend inwards or you land too stiffly. Over time this can hurt your knees. This is an automatic check, not a doctor''s advice — if it hurts, see a physio.',
 drill='Practise soft landings: step off a low box and land quietly with bent knees, knees pointing over your toes. 3 rounds of 8.'
 where code='landing_risk';
update public.analysis_rubric set title='Deep lunges',
 message='You often lunge very deep with your knee going past your toes. Doing this again and again puts a lot of strain on your knee. This is an automatic check, not a doctor''s advice — if it hurts, see a physio.',
 drill='Make your legs stronger for lunges: slow split-squats, 3 rounds of 8 on each leg, plus calf raises (rise up on your toes) to help soak up the impact.'
 where code='lunge_risk';
update public.analysis_rubric set title='Moving backwards',
 message='You often reach backwards while off balance. This strains your shoulder and lower back, and you could fall. This is an automatic check, not a doctor''s advice.',
 drill='Practise moving to the back of the court with a small scissor jump and landing balanced. Add tummy-strength work: dead-bugs, 3 rounds of 10.'
 where code='overreach_back';

update public.analysis_reports r set content = jsonb_set(r.content, '{findings}', (
  select jsonb_agg(case when rb.code is null then f else f || jsonb_build_object('title',rb.title,'message',rb.message,'drill',rb.drill) end order by ord)
  from jsonb_array_elements(r.content->'findings') with ordinality as x(f, ord)
  left join public.analysis_rubric rb on rb.code = f->>'code' and rb.lens='physio'))
where r.lens='physio' and jsonb_typeof(r.content->'findings')='array' and jsonb_array_length(r.content->'findings')>0;
