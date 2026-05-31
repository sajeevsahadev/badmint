-- =====================================================================
-- Badmint v6 — Facility Master + Bookings + Schedule
-- Run in Supabase SQL Editor AFTER v5_schema.sql
-- =====================================================================

-- ── Facility master (independent of clubs) ──
create table if not exists facilities (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  address     text,
  emirate     text check (emirate in (
    'Abu Dhabi','Dubai','Sharjah','Ajman',
    'Umm Al Quwain','Ras Al Khaimah','Fujairah'
  )),
  maps_url    text,
  description text,
  image_url   text,        -- paste any image URL; file-upload requires Supabase Storage (later)
  phone       text,
  website     text,
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now()
);

-- ── Weekly recurring time slots per facility ──
-- day_of_week: 0=Sunday … 6=Saturday
create table if not exists facility_schedule (
  id           uuid primary key default gen_random_uuid(),
  facility_id  uuid not null references facilities(id) on delete cascade,
  day_of_week  int  not null check (day_of_week between 0 and 6),
  start_time   time not null,
  end_time     time not null,
  slot_label   text,
  is_active    boolean not null default true
);

-- ── Bookings: which club is playing where and when ──
create table if not exists facility_bookings (
  id           uuid primary key default gen_random_uuid(),
  facility_id  uuid not null references facilities(id) on delete cascade,
  club_id      uuid not null references clubs(id)      on delete cascade,
  booked_date  date not null,
  start_time   time not null default '00:00',
  end_time     time,
  notes        text,
  auto_booked  boolean not null default false,
  created_by   uuid references auth.users(id),
  created_at   timestamptz not null default now(),
  unique(facility_id, club_id, booked_date, start_time)
);

-- ── Link each club to its home facility ──
alter table clubs add column if not exists facility_id uuid references facilities(id);

-- ── RLS ──
alter table facilities        enable row level security;
alter table facility_schedule enable row level security;
alter table facility_bookings enable row level security;

-- Facilities: public read; authenticated users can create; creator can update
do $$ begin create policy fac_read on facilities for select using (true);
exception when duplicate_object then null; end $$;
do $$ begin create policy fac_insert on facilities for insert
  with check (created_by = auth.uid());
exception when duplicate_object then null; end $$;
do $$ begin create policy fac_update on facilities for update
  using (created_by = auth.uid());
exception when duplicate_object then null; end $$;

-- Schedule: public read; only facility creator writes
do $$ begin create policy sched_read on facility_schedule for select using (true);
exception when duplicate_object then null; end $$;
do $$ begin create policy sched_write on facility_schedule for all
  using  (exists(select 1 from facilities f where f.id = facility_id and f.created_by = auth.uid()))
  with check (exists(select 1 from facilities f where f.id = facility_id and f.created_by = auth.uid()));
exception when duplicate_object then null; end $$;

-- Bookings: public read; club managers can insert for their club
do $$ begin create policy book_read on facility_bookings for select using (true);
exception when duplicate_object then null; end $$;
do $$ begin create policy book_insert on facility_bookings for insert
  with check (is_manager(club_id));
exception when duplicate_object then null; end $$;
do $$ begin create policy book_delete on facility_bookings for delete
  using (is_manager(club_id));
exception when duplicate_object then null; end $$;

-- ── Auto-booking trigger ──
-- When a match is recorded for a club with facility_id set,
-- auto-create a booking for that date (using the day's schedule slot if any).
create or replace function fn_auto_facility_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_fac  uuid;
  v_sched record;
begin
  select facility_id into v_fac from clubs where id = NEW.club_id;
  if v_fac is null then return NEW; end if;

  select * into v_sched
  from facility_schedule
  where facility_id = v_fac
    and day_of_week = extract(dow from NEW.played_on)::int
    and is_active = true
  order by start_time limit 1;

  insert into facility_bookings(
    facility_id, club_id, booked_date,
    start_time, end_time, auto_booked, created_by
  ) values (
    v_fac, NEW.club_id, NEW.played_on,
    coalesce(v_sched.start_time, '00:00'::time),
    v_sched.end_time,
    true, NEW.created_by
  )
  on conflict (facility_id, club_id, booked_date, start_time) do nothing;

  return NEW;
end;
$$;

drop trigger if exists trg_auto_facility_booking on matches;
create trigger trg_auto_facility_booking
  after insert on matches
  for each row execute function fn_auto_facility_booking();

-- ── Public RPCs ──

-- List all facilities (public, no auth needed)
drop function if exists get_facilities(text, text);
create function get_facilities(p_emirate text default null, p_search text default null)
returns table(
  id uuid, name text, address text, emirate text,
  maps_url text, description text, image_url text,
  club_count bigint, upcoming_count bigint
)
language sql stable security definer set search_path = public as $$
  select
    f.id, f.name, f.address, f.emirate,
    f.maps_url, f.description, f.image_url,
    count(distinct c.id)::bigint                                         as club_count,
    count(distinct fb.id) filter (where fb.booked_date >= current_date)::bigint as upcoming_count
  from facilities f
  left join clubs           c  on c.facility_id = f.id
  left join facility_bookings fb on fb.facility_id = f.id
  where (p_emirate is null or f.emirate = p_emirate)
    and (p_search  is null or
         f.name    ilike '%' || p_search || '%' or
         f.address ilike '%' || p_search || '%')
  group by f.id
  order by f.name;
$$;

-- Facility detail: schedule + upcoming bookings + linked clubs
create or replace function get_facility_detail(p_facility_id uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_fac      json;
  v_sched    json;
  v_bookings json;
  v_clubs    json;
begin
  select row_to_json(f) into v_fac
  from facilities f where id = p_facility_id;

  select json_agg(row_to_json(s) order by s.day_of_week, s.start_time) into v_sched
  from facility_schedule s
  where facility_id = p_facility_id and is_active = true;

  select json_agg(row_to_json(b) order by b.booked_date, b.start_time) into v_bookings
  from (
    select fb.id, fb.booked_date, fb.start_time, fb.end_time, fb.notes,
           c.name as club_name, c.id as club_id
    from facility_bookings fb
    join clubs c on c.id = fb.club_id
    where fb.facility_id = p_facility_id
      and fb.booked_date >= current_date - 7    -- last week + future
    order by fb.booked_date, fb.start_time
    limit 60
  ) b;

  select json_agg(row_to_json(cl) order by cl.name) into v_clubs
  from (
    select c.id, c.name, c.emirates
    from clubs c where c.facility_id = p_facility_id
  ) cl;

  return json_build_object(
    'facility', v_fac,
    'schedule', coalesce(v_sched, '[]'::json),
    'bookings', coalesce(v_bookings, '[]'::json),
    'clubs',    coalesce(v_clubs,    '[]'::json)
  );
end;
$$;

-- Create a facility
create or replace function create_facility(
  p_name        text,
  p_address     text    default null,
  p_emirate     text    default null,
  p_maps_url    text    default null,
  p_description text    default null,
  p_image_url   text    default null,
  p_phone       text    default null,
  p_website     text    default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into facilities(name, address, emirate, maps_url, description, image_url, phone, website, created_by)
  values (p_name, p_address, p_emirate, p_maps_url, p_description, p_image_url, p_phone, p_website, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- Update facility info (creator only)
create or replace function update_facility(
  p_id          uuid,
  p_name        text    default null,
  p_address     text    default null,
  p_emirate     text    default null,
  p_maps_url    text    default null,
  p_description text    default null,
  p_image_url   text    default null,
  p_phone       text    default null,
  p_website     text    default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from facilities where id = p_id and created_by = auth.uid()) then
    raise exception 'Not authorized';
  end if;
  update facilities set
    name        = coalesce(p_name,        name),
    address     = coalesce(p_address,     address),
    emirate     = coalesce(p_emirate,     emirate),
    maps_url    = coalesce(p_maps_url,    maps_url),
    description = coalesce(p_description, description),
    image_url   = coalesce(p_image_url,   image_url),
    phone       = coalesce(p_phone,       phone),
    website     = coalesce(p_website,     website)
  where id = p_id;
end;
$$;

-- Link/unlink a club to a facility (club manager)
create or replace function set_club_facility(p_club_id uuid, p_facility_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_manager(p_club_id) then raise exception 'Not authorized'; end if;
  update clubs set facility_id = p_facility_id where id = p_club_id;
end;
$$;

-- Add a recurring schedule slot (facility creator)
create or replace function add_facility_slot(
  p_facility_id uuid,
  p_day         int,
  p_start       time,
  p_end         time,
  p_label       text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not exists(select 1 from facilities where id = p_facility_id and created_by = auth.uid()) then
    raise exception 'Not authorized';
  end if;
  insert into facility_schedule(facility_id, day_of_week, start_time, end_time, slot_label)
  values (p_facility_id, p_day, p_start, p_end, p_label)
  returning id into v_id;
  return v_id;
end;
$$;

-- Delete a schedule slot (facility creator)
create or replace function delete_facility_slot(p_slot_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from facility_schedule
  where id = p_slot_id
    and exists(select 1 from facilities f where f.id = facility_id and f.created_by = auth.uid());
end;
$$;

grant execute on function get_facilities(text, text)                     to authenticated, anon;
grant execute on function get_facility_detail(uuid)                      to authenticated, anon;
grant execute on function create_facility(text,text,text,text,text,text,text,text) to authenticated;
grant execute on function update_facility(uuid,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function set_club_facility(uuid, uuid)                  to authenticated;
grant execute on function add_facility_slot(uuid, int, time, time, text) to authenticated;
grant execute on function delete_facility_slot(uuid)                     to authenticated;
