-- v148: Coach Vision usage & cost tracking + commentary audio.
-- Every AI job writes one ai_usage row with MEASURED units (compute seconds, cores, GPU, Gemini tokens,
-- TTS characters) and who / which club / which video triggered it. A trigger prices the row from
-- ai_cost_rates (admin-editable, so estimates can be corrected against the real Modal / Google bills).
-- admin_ai_overview() powers the Admin Panel "AI" tab: per club, per member, per feature, cost, margin.
-- Applied to project bdmiirppiyopmdfrztoz via MCP.

create table if not exists public.ai_cost_rates (
  key        text primary key,
  usd        numeric not null,
  unit       text not null,
  note       text,
  updated_at timestamptz not null default now()
);
insert into public.ai_cost_rates (key, usd, unit, note) values
  ('modal_cpu_core_s',      0.0000131, 'per CPU core-second',            'Modal CPU'),
  ('modal_mem_gib_s',       0.00000222,'per GiB-second of memory',       'Modal memory'),
  ('modal_l4_gpu_s',        0.000222,  'per L4 GPU-second',              'Modal L4 GPU'),
  ('gemini_text_in_1m',     0.30,      'per 1M input tokens',            'Gemini flash text — verify against AI Studio billing'),
  ('gemini_text_out_1m',    2.50,      'per 1M output+thinking tokens',  'Gemini flash text — verify against AI Studio billing'),
  ('gemini_tts_in_1m',      0.50,      'per 1M input tokens',            'Gemini TTS — verify against AI Studio billing'),
  ('gemini_tts_out_1m',     10.00,     'per 1M audio output tokens',     'Gemini TTS — verify against AI Studio billing'),
  ('usd_to_aed',            3.6725,    'AED per USD',                    'for display')
on conflict (key) do nothing;
alter table public.ai_cost_rates enable row level security;
drop policy if exists acr_admin on public.ai_cost_rates;
create policy acr_admin on public.ai_cost_rates for all using (public.is_app_admin()) with check (public.is_app_admin());

create table if not exists public.ai_usage (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id    uuid references auth.users(id) on delete set null,
  club_id    uuid references public.clubs(id) on delete set null,
  video_id   uuid references public.match_videos(id) on delete set null,
  run_id     uuid references public.analysis_runs(id) on delete set null,
  feature    text not null check (feature in ('index','quick_report','deep_coaching','commentary','commentary_audio','chat')),
  provider   text not null check (provider in ('modal','gemini')),
  units      jsonb not null default '{}',
  cost_usd   numeric(14,6) not null default 0,
  meta       jsonb not null default '{}'
);
create index if not exists idx_aiu_created on public.ai_usage(created_at desc);
create index if not exists idx_aiu_club    on public.ai_usage(club_id, created_at desc);
create index if not exists idx_aiu_user    on public.ai_usage(user_id, created_at desc);
alter table public.ai_usage enable row level security;
drop policy if exists aiu_admin on public.ai_usage;
create policy aiu_admin on public.ai_usage for select using (public.is_app_admin());

-- Price a row from its units. Modal: wall_s × (cores×cpu + mem_gib×mem + gpu). Gemini: tokens × rates.
create or replace function public._ai_rate(p_key text) returns numeric language sql stable as $$
  select coalesce((select usd from public.ai_cost_rates where key = p_key), 0);
$$;

create or replace function public.ai_usage_price() returns trigger language plpgsql as $$
declare u jsonb := new.units; w numeric;
begin
  -- fill club from the video when the caller didn't pass it
  if new.club_id is null and new.video_id is not null then
    select club_id into new.club_id from public.match_videos where id = new.video_id;
  end if;
  if new.user_id is null and new.run_id is not null then
    select created_by into new.user_id from public.analysis_runs where id = new.run_id;
  end if;
  if new.provider = 'modal' then
    w := coalesce((u->>'wall_s')::numeric, 0);
    new.cost_usd := w * ( coalesce((u->>'cpu_cores')::numeric, 0) * public._ai_rate('modal_cpu_core_s')
                        + coalesce((u->>'mem_gib')::numeric, 0)   * public._ai_rate('modal_mem_gib_s')
                        + case when u->>'gpu' = 'L4' then public._ai_rate('modal_l4_gpu_s') else 0 end );
  elsif new.feature = 'commentary_audio' then
    new.cost_usd := coalesce((u->>'input_tokens')::numeric, 0)  / 1e6 * public._ai_rate('gemini_tts_in_1m')
                  + coalesce((u->>'output_tokens')::numeric, 0) / 1e6 * public._ai_rate('gemini_tts_out_1m');
  else
    new.cost_usd := coalesce((u->>'input_tokens')::numeric, 0) / 1e6 * public._ai_rate('gemini_text_in_1m')
                  + (coalesce((u->>'output_tokens')::numeric, 0) + coalesce((u->>'thinking_tokens')::numeric, 0))
                    / 1e6 * public._ai_rate('gemini_text_out_1m');
  end if;
  return new;
end;
$$;
drop trigger if exists trg_ai_usage_price on public.ai_usage;
create trigger trg_ai_usage_price before insert on public.ai_usage for each row execute function public.ai_usage_price();

-- Who started a run (edge functions run as service role, so pass it explicitly).
drop function if exists public.start_analysis_run(uuid, text, boolean, text);
create or replace function public.start_analysis_run(p_video_id uuid, p_kind text, p_is_mock boolean default false,
                                                     p_engine text default null, p_user_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ver int;
begin
  perform pg_advisory_xact_lock(hashtext(p_video_id::text || p_kind));
  select coalesce(max(version), 0) + 1 into v_ver from public.analysis_runs where video_id = p_video_id and kind = p_kind;
  insert into public.analysis_runs (video_id, kind, version, status, is_mock, engine, created_by)
  values (p_video_id, p_kind, v_ver, 'analyzing', p_is_mock, p_engine, coalesce(p_user_id, auth.uid())) returning id into v_id;
  if p_kind = 'simple' then
    update public.match_videos set status = 'analyzing', error = null where id = p_video_id;
  else
    update public.match_videos set deep_status = 'analyzing', deep_error = null, deep_requested_at = now() where id = p_video_id;
  end if;
  return v_id;
end;
$$;
revoke execute on function public.start_analysis_run(uuid, text, boolean, text, uuid) from public, anon, authenticated;
grant  execute on function public.start_analysis_run(uuid, text, boolean, text, uuid) to service_role;

-- Commentary audio (AI voice) per line.
alter table public.analysis_commentary add column if not exists audio_path text;

-- Admin overview -------------------------------------------------------------------------------------
create or replace function public.admin_ai_overview(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := now() - make_interval(days => greatest(1, p_days)); v_aed numeric := public._ai_rate('usd_to_aed');
begin
  if not public.is_app_admin() then raise exception 'Not allowed'; end if;
  return jsonb_build_object(
    'days', p_days,
    'usd_to_aed', v_aed,
    'totals', (select jsonb_build_object(
        'cost_usd', coalesce(round(sum(cost_usd)::numeric, 4), 0),
        'events', count(*), 'users', count(distinct user_id), 'clubs', count(distinct club_id),
        'videos', count(distinct video_id))
       from public.ai_usage where created_at >= v_from),
    'by_feature', coalesce((select jsonb_agg(x order by x->>'feature') from (
        select jsonb_build_object('feature', feature, 'events', count(*), 'cost_usd', round(sum(cost_usd)::numeric, 4)) x
          from public.ai_usage where created_at >= v_from group by feature) f), '[]'::jsonb),
    'runs', (select jsonb_build_object(
        'quick', count(*) filter (where kind = 'simple'), 'deep', count(*) filter (where kind = 'deep'),
        'failed', count(*) filter (where status = 'failed'))
       from public.analysis_runs where created_at >= v_from and not is_mock),
    'by_club', coalesce((select jsonb_agg(c order by (c->>'cost_usd')::numeric desc) from (
        select jsonb_build_object(
          'club_id', u.club_id, 'club', coalesce(cl.name, '—'),
          'members_using', count(distinct u.user_id),
          'members_total', (select count(*) from public.club_members m where m.club_id = u.club_id),
          'videos', count(distinct u.video_id),
          'quick', count(*) filter (where u.feature = 'quick_report'),
          'deep', count(*) filter (where u.feature = 'deep_coaching'),
          'chats', count(*) filter (where u.feature = 'chat'),
          'cost_usd', round(sum(u.cost_usd)::numeric, 4)) c
        from public.ai_usage u left join public.clubs cl on cl.id = u.club_id
        where u.created_at >= v_from group by u.club_id, cl.name) q), '[]'::jsonb),
    'by_user', coalesce((select jsonb_agg(m order by (m->>'cost_usd')::numeric desc) from (
        select jsonb_build_object(
          'user_id', u.user_id,
          'name', coalesce(up.nickname, up.full_name, au.raw_user_meta_data->>'full_name', au.email, '—'),
          'email', au.email,
          'clubs', (select string_agg(distinct cl.name, ', ') from public.ai_usage u2 join public.clubs cl on cl.id = u2.club_id
                     where u2.user_id = u.user_id and u2.created_at >= v_from),
          'early_access', exists (select 1 from public.app_roles r where r.user_id = u.user_id and r.role in ('early_access','app_admin')),
          'plan', (select sp.name from public.user_subscriptions us join public.subscription_plans sp on sp.code = us.plan_code
                    where us.user_id = u.user_id and us.status in ('active','trialing','comp') order by us.created_at desc limit 1),
          'videos', count(distinct u.video_id),
          'quick', count(*) filter (where u.feature = 'quick_report'),
          'deep', count(*) filter (where u.feature = 'deep_coaching'),
          'chats', count(*) filter (where u.feature = 'chat'),
          'audio', count(*) filter (where u.feature = 'commentary_audio'),
          'cost_usd', round(sum(u.cost_usd)::numeric, 4),
          'last_used', max(u.created_at)) m
        from public.ai_usage u
        left join auth.users au on au.id = u.user_id
        left join public.user_profiles up on up.user_id = u.user_id
        where u.created_at >= v_from group by u.user_id, up.nickname, up.full_name, au.raw_user_meta_data, au.email) q), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(r) from (
        select jsonb_build_object(
          'at', u.created_at, 'feature', u.feature, 'provider', u.provider, 'cost_usd', round(u.cost_usd::numeric, 5),
          'units', u.units, 'club', cl.name, 'video', mv.title,
          'who', coalesce(up.nickname, up.full_name, au.email, '—')) r
        from public.ai_usage u
        left join public.clubs cl on cl.id = u.club_id
        left join public.match_videos mv on mv.id = u.video_id
        left join auth.users au on au.id = u.user_id
        left join public.user_profiles up on up.user_id = u.user_id
        where u.created_at >= v_from order by u.created_at desc limit 60) q), '[]'::jsonb),
    'rates', coalesce((select jsonb_agg(to_jsonb(r) order by r.key) from public.ai_cost_rates r), '[]'::jsonb));
end;
$$;
grant execute on function public.admin_ai_overview(integer) to authenticated;

create or replace function public.admin_set_ai_rate(p_key text, p_usd numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_app_admin() then raise exception 'Not allowed'; end if;
  update public.ai_cost_rates set usd = p_usd, updated_at = now() where key = p_key;
end;
$$;
grant execute on function public.admin_set_ai_rate(text, numeric) to authenticated;
