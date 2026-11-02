-- Phase 2: subscription / entitlement provisioning. No live card processing yet (provider
-- integration + company registration pending) — this is the data model + admin controls so
-- plans and entitlements exist and can be managed/comped manually now.
-- Applied to bdmiirppiyopmdfrztoz via MCP. See v103 migration for full body.

create table if not exists public.subscription_plans (
  code text primary key, name text not null, price_cents integer not null default 0,
  currency text not null default 'AED',
  interval text not null default 'month' check (interval in ('month','year')),
  features jsonb not null default '{}', is_active boolean not null default true, sort integer not null default 0
);
create table if not exists public.user_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_code text not null references public.subscription_plans(code),
  status text not null default 'active' check (status in ('active','trialing','past_due','canceled','comp')),
  provider text not null default 'manual' check (provider in ('manual','stripe','ziina')),
  provider_ref text, current_period_start timestamptz default now(), current_period_end timestamptz,
  notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists uniq_user_live_sub on public.user_subscriptions(user_id)
  where status in ('active','trialing','comp');
alter table public.subscription_plans enable row level security;
alter table public.user_subscriptions enable row level security;
drop policy if exists sp_read on public.subscription_plans;
create policy sp_read on public.subscription_plans for select using (is_active or is_app_admin());
drop policy if exists us_read_own on public.user_subscriptions;
create policy us_read_own on public.user_subscriptions for select using (user_id = auth.uid() or is_app_admin());
-- Seed: free / player_pro / club. RPCs: get_subscription_plans, get_my_subscription,
-- admin_set_subscription(user, plan, status, period_end, provider, notes), admin_list_subscriptions.
-- (Full bodies in the applied migration.)
