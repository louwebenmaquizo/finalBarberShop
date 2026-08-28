-- Initial Supabase schema for the barber application.
-- All application identifiers are UUIDs. Compatibility views retain the
-- legacy *_id response keys used by the Flutter application.

begin;

create extension if not exists citext with schema extensions;
create extension if not exists btree_gist with schema extensions;

create type public.app_role as enum (
  'admin',
  'manager',
  'cashier',
  'barber',
  'staff',
  'customer'
);

create type public.appointment_status as enum (
  'pending',
  'booked',
  'confirmed',
  'checked-in',
  'in-service',
  'in_progress',
  'completed',
  'canceled',
  'declined',
  'no-show'
);

create type public.appointment_source as enum ('web', 'phone', 'walk-in');
create type public.payment_method_type as enum ('cash', 'card', 'mobile');
create type public.transaction_status as enum ('pending', 'completed', 'refunded', 'failed');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username extensions.citext not null unique,
  role public.app_role not null default 'customer',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references public.profiles (id) on delete set null,
  full_name text not null check (length(btrim(full_name)) between 1 and 100),
  phone text not null check (length(btrim(phone)) between 3 and 32),
  email extensions.citext,
  registration_date date not null default current_date,
  date_of_birth date,
  gender text check (gender is null or gender in ('Male', 'Female', 'Other')),
  notes text,
  profile_picture text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index customers_phone_key on public.customers (phone);
create unique index customers_email_key on public.customers (email) where email is not null;

create table public.service_categories (
  id uuid primary key default gen_random_uuid(),
  name extensions.citext not null unique check (length(btrim(name::text)) between 1 and 100),
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  name extensions.citext not null unique check (length(btrim(name::text)) between 1 and 100),
  category_id uuid references public.service_categories (id) on delete set null,
  duration_minutes integer not null check (duration_minutes > 0 and duration_minutes <= 1440),
  price numeric(10, 2) not null check (price >= 0),
  cost numeric(10, 2) check (cost is null or cost >= 0),
  description text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.staff (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references public.profiles (id) on delete set null,
  name text not null check (length(btrim(name)) between 1 and 100),
  phone text,
  email extensions.citext,
  role text not null check (length(btrim(role)) between 1 and 50),
  skills text,
  pay_rate numeric(10, 2) check (pay_rate is null or pay_rate >= 0),
  commission_rate numeric(5, 3) not null default 0
    check (commission_rate >= 0 and commission_rate <= 100),
  is_active boolean not null default true,
  profile_photo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index staff_phone_key on public.staff (phone) where phone is not null;
create unique index staff_email_key on public.staff (email) where email is not null;
create unique index staff_name_key on public.staff (lower(btrim(name)));

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  staff_id uuid references public.staff (id) on delete set null,
  service_id uuid references public.services (id) on delete set null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  status public.appointment_status not null default 'pending',
  source public.appointment_source not null default 'web',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint appointments_end_after_start check (end_time > start_time),
  constraint appointments_id_customer_key unique (id, customer_id)
);

alter table public.appointments
  add constraint appointments_staff_no_overlap
  exclude using gist (
    staff_id with =,
    tstzrange(start_time, end_time, '[)') with &&
  )
  where (
    staff_id is not null
    and status not in ('canceled', 'declined', 'no-show')
  );

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid unique references public.appointments (id) on delete set null,
  customer_id uuid references public.customers (id) on delete set null,
  amount numeric(10, 2) not null check (amount > 0),
  payment_method public.payment_method_type not null,
  tip_amount numeric(10, 2) not null default 0 check (tip_amount >= 0),
  tax_amount numeric(10, 2) not null default 0 check (tax_amount >= 0),
  staff_id uuid references public.staff (id) on delete set null,
  status public.transaction_status not null default 'completed',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null,
  customer_id uuid not null,
  rating integer not null check (rating between 1 and 5),
  comments text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint feedback_appointment_customer_key unique (appointment_id, customer_id),
  constraint feedback_appointment_customer_fkey
    foreign key (appointment_id, customer_id)
    references public.appointments (id, customer_id)
    on delete cascade
);

create index services_category_id_idx on public.services (category_id);
create index staff_user_id_idx on public.staff (user_id);
create index appointments_customer_start_idx on public.appointments (customer_id, start_time desc);
create index appointments_staff_start_idx on public.appointments (staff_id, start_time);
create index appointments_service_id_idx on public.appointments (service_id);
create index appointments_status_start_idx on public.appointments (status, start_time);
create index transactions_customer_created_idx on public.transactions (customer_id, created_at desc);
create index transactions_staff_created_idx on public.transactions (staff_id, created_at desc);
create index transactions_status_created_idx on public.transactions (status, created_at desc);
create index feedback_customer_created_idx on public.feedback (customer_id, created_at desc);

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger customers_set_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

create trigger service_categories_set_updated_at
before update on public.service_categories
for each row execute function public.set_updated_at();

create trigger services_set_updated_at
before update on public.services
for each row execute function public.set_updated_at();

create trigger staff_set_updated_at
before update on public.staff
for each row execute function public.set_updated_at();

create trigger appointments_set_updated_at
before update on public.appointments
for each row execute function public.set_updated_at();

create trigger transactions_set_updated_at
before update on public.transactions
for each row execute function public.set_updated_at();

create trigger feedback_set_updated_at
before update on public.feedback
for each row execute function public.set_updated_at();

-- Derive appointment end times from the selected service. If a historical
-- service is deleted and the FK becomes null, preserve the existing end time.
create function public.derive_appointment_end_time()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_duration integer;
begin
  if new.service_id is null then
    if new.end_time is null then
      raise exception 'An end time is required when no service is selected'
        using errcode = '23514';
    end if;
    return new;
  end if;

  select s.duration_minutes
    into v_duration
    from public.services as s
   where s.id = new.service_id;

  if v_duration is null then
    raise exception 'Service not found'
      using errcode = '23503';
  end if;

  new.end_time := new.start_time + make_interval(mins => v_duration);
  return new;
end;
$$;

create trigger appointments_derive_end_time
before insert or update of start_time, service_id on public.appointments
for each row execute function public.derive_appointment_end_time();

-- Auth signup always creates a customer-role profile. Client metadata is never
-- allowed to choose an elevated role.
create function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base_username text;
  v_username text;
  v_full_name text;
  v_phone text;
  v_gender text;
  v_date_of_birth date;
  v_date_raw text;
begin
  v_base_username := lower(
    regexp_replace(
      coalesce(
        nullif(btrim(new.raw_user_meta_data ->> 'username'), ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'user'
      ),
      '[^a-zA-Z0-9_.-]+',
      '_',
      'g'
    )
  );
  v_base_username := left(nullif(btrim(v_base_username, '._-'), ''), 40);
  v_base_username := coalesce(v_base_username, 'user');
  v_username := v_base_username;

  if exists (select 1 from public.profiles as p where p.username = v_username) then
    v_username := left(v_base_username, 40) || '_' || left(replace(new.id::text, '-', ''), 8);
  end if;

  insert into public.profiles (id, username, role, is_active)
  values (new.id, v_username, 'customer', true);

  v_full_name := nullif(btrim(new.raw_user_meta_data ->> 'full_name'), '');
  v_phone := nullif(btrim(new.raw_user_meta_data ->> 'phone'), '');
  v_gender := nullif(btrim(new.raw_user_meta_data ->> 'gender'), '');
  if v_gender not in ('Male', 'Female', 'Other') then
    v_gender := null;
  end if;

  v_date_raw := nullif(btrim(new.raw_user_meta_data ->> 'date_of_birth'), '');
  if v_date_raw is not null then
    begin
      v_date_of_birth := v_date_raw::date;
    exception when invalid_datetime_format or datetime_field_overflow then
      v_date_of_birth := null;
    end;
  end if;

  if v_full_name is not null and v_phone is not null then
    insert into public.customers (
      user_id,
      full_name,
      phone,
      email,
      date_of_birth,
      gender,
      notes
    )
    values (
      new.id,
      v_full_name,
      v_phone,
      new.email,
      v_date_of_birth,
      v_gender,
      nullif(btrim(new.raw_user_meta_data ->> 'notes'), '')
    );
  end if;

  return new;
exception
  when unique_violation then
    raise exception 'An account with that username, email, or phone already exists'
      using errcode = '23505';
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- RLS helper functions live outside exposed schemas and bypass table RLS only
-- to answer small authorization questions.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

create function private.current_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
    from public.profiles as p
   where p.id = auth.uid()
     and p.is_active;
$$;

create function private.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.profiles as p
     where p.id = auth.uid()
       and p.is_active
  );
$$;

create function private.is_management()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_role() in ('admin', 'manager'), false);
$$;

create function private.is_operations()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_role() in ('admin', 'manager', 'cashier'), false);
$$;

create function private.current_customer_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id
    from public.customers as c
    join public.profiles as p on p.id = c.user_id
   where c.user_id = auth.uid()
     and p.is_active;
$$;

create function private.current_staff_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id
    from public.staff as s
    join public.profiles as p on p.id = s.user_id
   where s.user_id = auth.uid()
     and s.is_active
     and p.is_active;
$$;

create function private.can_view_appointment(p_appointment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.is_operations(), false)
      or exists (
        select 1
          from public.appointments as a
         where a.id = p_appointment_id
           and (
             a.customer_id = private.current_customer_id()
             or a.staff_id = private.current_staff_id()
           )
      );
$$;

create function private.can_view_customer(p_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.is_operations(), false)
      or p_customer_id = private.current_customer_id()
      or exists (
        select 1
          from public.appointments as a
         where a.customer_id = p_customer_id
           and a.staff_id = private.current_staff_id()
      );
$$;

create function private.can_submit_feedback(p_appointment_id uuid, p_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_customer_id = private.current_customer_id()
     and exists (
       select 1
         from public.appointments as a
        where a.id = p_appointment_id
          and a.customer_id = p_customer_id
          and a.status = 'completed'
     );
$$;

revoke all on all functions in schema private from public;
grant execute on all functions in schema private to anon, authenticated;

alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.service_categories enable row level security;
alter table public.services enable row level security;
alter table public.staff enable row level security;
alter table public.appointments enable row level security;
alter table public.transactions enable row level security;
alter table public.feedback enable row level security;

create policy profiles_select_self_or_management
on public.profiles for select to authenticated
using (id = auth.uid() or private.is_management());

create policy profiles_update_management
on public.profiles for update to authenticated
using (private.is_management())
with check (private.is_management());

create policy customers_select_owner_or_operations
on public.customers for select to authenticated
using (user_id = auth.uid() or private.is_operations());

create policy customers_insert_management
on public.customers for insert to authenticated
with check (private.is_management());

create policy customers_update_owner_or_management
on public.customers for update to authenticated
using (user_id = auth.uid() or private.is_management())
with check (user_id = auth.uid() or private.is_management());

create policy customers_delete_management
on public.customers for delete to authenticated
using (private.is_management());

create policy service_categories_read
on public.service_categories for select to anon, authenticated
using (true);

create policy service_categories_write_management
on public.service_categories for all to authenticated
using (private.is_management())
with check (private.is_management());

create policy services_read_catalog
on public.services for select to anon, authenticated
using (is_active or private.is_management());

create policy services_write_management
on public.services for all to authenticated
using (private.is_management())
with check (private.is_management());

create policy staff_select_self_or_management
on public.staff for select to authenticated
using (user_id = auth.uid() or private.is_management());

create policy staff_write_management
on public.staff for all to authenticated
using (private.is_management())
with check (private.is_management());

create policy appointments_select_visible
on public.appointments for select to authenticated
using (
  private.is_operations()
  or customer_id = private.current_customer_id()
  or staff_id = private.current_staff_id()
);

create policy appointments_write_management
on public.appointments for all to authenticated
using (private.is_management())
with check (private.is_management());

create policy transactions_select_visible
on public.transactions for select to authenticated
using (
  private.is_operations()
  or customer_id = private.current_customer_id()
  or staff_id = private.current_staff_id()
);

create policy transactions_write_operations
on public.transactions for all to authenticated
using (private.is_operations())
with check (private.is_operations());

create policy feedback_select_visible
on public.feedback for select to authenticated
using (
  private.is_operations()
  or customer_id = private.current_customer_id()
  or private.can_view_appointment(appointment_id)
);

create policy feedback_insert_owner
on public.feedback for insert to authenticated
with check (private.can_submit_feedback(appointment_id, customer_id));

create policy feedback_update_owner_or_management
on public.feedback for update to authenticated
using (
  private.can_submit_feedback(appointment_id, customer_id)
  or private.is_management()
)
with check (
  private.can_submit_feedback(appointment_id, customer_id)
  or private.is_management()
);

create policy feedback_delete_owner_or_management
on public.feedback for delete to authenticated
using (customer_id = private.current_customer_id() or private.is_management());

-- Compatibility views. Safe directory/detail views use narrowly scoped
-- security-definer row providers while the exposed views remain invoker views.
create view public.service_catalog
with (security_invoker = true)
as
select
  s.id as service_id,
  s.name,
  s.category_id,
  c.name as category_name,
  s.duration_minutes,
  s.price,
  (case when private.is_management() then s.cost end)::numeric(10, 2) as cost,
  s.description,
  s.image_url,
  s.is_active,
  s.created_at,
  s.updated_at
from public.services as s
left join public.service_categories as c on c.id = s.category_id;

create view public.category_catalog
with (security_invoker = true)
as
select
  c.id as category_id,
  c.name,
  c.description,
  c.created_at,
  c.updated_at,
  count(s.id)::integer as service_count
from public.service_categories as c
left join public.services as s on s.category_id = c.id
group by c.id;

create function private.staff_directory_rows()
returns table (
  staff_id uuid,
  user_id uuid,
  username extensions.citext,
  name text,
  phone text,
  email extensions.citext,
  role text,
  skills text,
  pay_rate numeric,
  commission_rate numeric,
  profile_photo text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    s.id,
    case when private.is_management() or s.user_id = auth.uid() then s.user_id end,
    case when private.is_management() or s.user_id = auth.uid() then p.username end,
    s.name,
    case when private.is_management() or s.user_id = auth.uid() then s.phone end,
    case when private.is_management() or s.user_id = auth.uid() then s.email end,
    s.role,
    s.skills,
    case when private.is_management() or s.user_id = auth.uid() then s.pay_rate end,
    case when private.is_management() or s.user_id = auth.uid() then s.commission_rate end,
    s.profile_photo,
    s.is_active,
    s.created_at,
    s.updated_at
  from public.staff as s
  left join public.profiles as p on p.id = s.user_id
  where s.is_active or private.is_management() or s.user_id = auth.uid();
$$;

create view public.staff_directory
with (security_invoker = true)
as
select * from private.staff_directory_rows();

create function private.appointment_detail_rows()
returns table (
  appointment_id uuid,
  customer_id uuid,
  staff_id uuid,
  service_id uuid,
  start_time timestamptz,
  end_time timestamptz,
  status text,
  source text,
  notes text,
  created_at timestamptz,
  updated_at timestamptz,
  customer_name text,
  customer_phone text,
  customer_photo text,
  staff_name text,
  staff_photo text,
  service_name extensions.citext,
  service_image text,
  description text,
  service_price numeric,
  duration_minutes integer,
  category_name extensions.citext,
  "date" date,
  "time" time without time zone
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.id,
    a.customer_id,
    a.staff_id,
    a.service_id,
    a.start_time,
    a.end_time,
    a.status::text,
    a.source::text,
    a.notes,
    a.created_at,
    a.updated_at,
    c.full_name,
    c.phone,
    c.profile_picture,
    st.name,
    st.profile_photo,
    sv.name,
    sv.image_url,
    sv.description,
    sv.price,
    sv.duration_minutes,
    sc.name,
    (a.start_time at time zone 'Asia/Singapore')::date,
    (a.start_time at time zone 'Asia/Singapore')::time
  from public.appointments as a
  join public.customers as c on c.id = a.customer_id
  left join public.staff as st on st.id = a.staff_id
  left join public.services as sv on sv.id = a.service_id
  left join public.service_categories as sc on sc.id = sv.category_id
  where private.can_view_appointment(a.id);
$$;

create view public.appointment_details
with (security_invoker = true)
as
select * from private.appointment_detail_rows();

create function private.transaction_detail_rows()
returns table (
  transaction_id uuid,
  appointment_id uuid,
  customer_id uuid,
  customer_name text,
  amount numeric,
  payment_method text,
  tip_amount numeric,
  tax_amount numeric,
  staff_id uuid,
  staff_name text,
  status text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    t.id,
    t.appointment_id,
    t.customer_id,
    c.full_name,
    t.amount,
    t.payment_method::text,
    t.tip_amount,
    t.tax_amount,
    t.staff_id,
    st.name,
    t.status::text,
    t.created_at,
    t.updated_at
  from public.transactions as t
  left join public.customers as c on c.id = t.customer_id
  left join public.staff as st on st.id = t.staff_id
  where private.is_operations()
     or t.customer_id = private.current_customer_id()
     or t.staff_id = private.current_staff_id();
$$;

create view public.transaction_details
with (security_invoker = true)
as
select * from private.transaction_detail_rows();

revoke all on function private.staff_directory_rows() from public;
revoke all on function private.appointment_detail_rows() from public;
revoke all on function private.transaction_detail_rows() from public;
grant execute on function private.staff_directory_rows() to anon, authenticated;
grant execute on function private.appointment_detail_rows() to authenticated;
grant execute on function private.transaction_detail_rows() to authenticated;

-- Controlled application mutations.
create function public.create_appointment(
  p_staff_id uuid,
  p_service_id uuid,
  p_start_time timestamptz,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_id uuid;
  v_duration integer;
  v_appointment_id uuid;
  v_end_time timestamptz;
begin
  if auth.uid() is null or not private.is_active_user() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  v_customer_id := private.current_customer_id();
  if v_customer_id is null then
    raise exception 'Customer profile not found' using errcode = '42501';
  end if;

  if p_start_time <= now() then
    raise exception 'Appointment time must be in the future' using errcode = '22023';
  end if;

  select s.duration_minutes
    into v_duration
    from public.services as s
   where s.id = p_service_id
     and s.is_active;
  if v_duration is null then
    raise exception 'Active service not found' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.staff as s where s.id = p_staff_id and s.is_active
  ) then
    raise exception 'Active staff member not found' using errcode = '22023';
  end if;

  v_end_time := p_start_time + make_interval(mins => v_duration);

  insert into public.appointments (
    customer_id,
    staff_id,
    service_id,
    start_time,
    end_time,
    status,
    source,
    notes
  )
  values (
    v_customer_id,
    p_staff_id,
    p_service_id,
    p_start_time,
    v_end_time,
    'pending',
    'web',
    nullif(btrim(p_notes), '')
  )
  returning id, end_time into v_appointment_id, v_end_time;

  return jsonb_build_object(
    'appointment_id', v_appointment_id,
    'customer_id', v_customer_id,
    'staff_id', p_staff_id,
    'service_id', p_service_id,
    'start_time', p_start_time,
    'end_time', v_end_time,
    'status', 'pending'
  );
exception
  when exclusion_violation then
    raise exception 'The selected staff member is not available at that time'
      using errcode = '23P01';
end;
$$;

create function public.reschedule_appointment(
  p_appointment_id uuid,
  p_start_time timestamptz,
  p_staff_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_appointment public.appointments%rowtype;
  v_staff_id uuid;
  v_duration integer;
  v_end_time timestamptz;
  v_customer_owned boolean;
begin
  if auth.uid() is null or not private.is_active_user() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_appointment
    from public.appointments
   where id = p_appointment_id
   for update;
  if not found then
    raise exception 'Appointment not found' using errcode = 'P0002';
  end if;

  v_customer_owned := v_appointment.customer_id = private.current_customer_id();
  if not private.is_operations() and not v_customer_owned then
    raise exception 'Not allowed to reschedule this appointment' using errcode = '42501';
  end if;

  if v_customer_owned and v_appointment.status not in ('pending', 'booked', 'confirmed') then
    raise exception 'This appointment can no longer be rescheduled' using errcode = '22023';
  end if;

  if p_start_time <= now() then
    raise exception 'Appointment time must be in the future' using errcode = '22023';
  end if;

  v_staff_id := coalesce(p_staff_id, v_appointment.staff_id);
  if v_staff_id is null or not exists (
    select 1 from public.staff as s where s.id = v_staff_id and s.is_active
  ) then
    raise exception 'Active staff member not found' using errcode = '22023';
  end if;

  select s.duration_minutes into v_duration
    from public.services as s
   where s.id = v_appointment.service_id
     and s.is_active;
  if v_duration is null then
    raise exception 'Active service not found' using errcode = '22023';
  end if;

  v_end_time := p_start_time + make_interval(mins => v_duration);

  update public.appointments
     set start_time = p_start_time,
         end_time = v_end_time,
         staff_id = v_staff_id
   where id = p_appointment_id;

  return jsonb_build_object(
    'appointment_id', p_appointment_id,
    'staff_id', v_staff_id,
    'start_time', p_start_time,
    'end_time', v_end_time,
    'status', v_appointment.status::text
  );
exception
  when exclusion_violation then
    raise exception 'The selected staff member is not available at that time'
      using errcode = '23P01';
end;
$$;

create function public.complete_appointment(
  p_appointment_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_tip_amount numeric default 0,
  p_tax_amount numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_appointment public.appointments%rowtype;
  v_transaction_id uuid;
  v_method public.payment_method_type;
  v_authorized boolean;
begin
  if auth.uid() is null or not private.is_active_user() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0
     or coalesce(p_tip_amount, 0) < 0
     or coalesce(p_tax_amount, 0) < 0 then
    raise exception 'Payment amounts are invalid' using errcode = '22023';
  end if;

  begin
    v_method := lower(btrim(p_payment_method))::public.payment_method_type;
  exception when invalid_text_representation then
    raise exception 'Payment method must be cash, card, or mobile' using errcode = '22023';
  end;

  select * into v_appointment
    from public.appointments
   where id = p_appointment_id
   for update;
  if not found then
    raise exception 'Appointment not found' using errcode = 'P0002';
  end if;

  v_authorized := private.is_operations()
    or v_appointment.staff_id = private.current_staff_id();
  if not v_authorized then
    raise exception 'Not allowed to complete this appointment' using errcode = '42501';
  end if;

  if v_appointment.staff_id is null then
    raise exception 'Appointment has no assigned staff member' using errcode = '22023';
  end if;

  if v_appointment.status not in (
    'booked', 'confirmed', 'checked-in', 'in-service', 'in_progress', 'completed'
  ) then
    raise exception 'Appointment is not ready for completion' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.transactions as t where t.appointment_id = p_appointment_id
  ) then
    raise exception 'A transaction already exists for this appointment' using errcode = '23505';
  end if;

  update public.appointments
     set status = 'completed'
   where id = p_appointment_id;

  insert into public.transactions (
    appointment_id,
    customer_id,
    amount,
    payment_method,
    tip_amount,
    tax_amount,
    staff_id,
    status
  )
  values (
    p_appointment_id,
    v_appointment.customer_id,
    p_amount,
    v_method,
    coalesce(p_tip_amount, 0),
    coalesce(p_tax_amount, 0),
    v_appointment.staff_id,
    'completed'
  )
  returning id into v_transaction_id;

  return jsonb_build_object(
    'appointment_id', p_appointment_id,
    'transaction_id', v_transaction_id,
    'customer_id', v_appointment.customer_id,
    'staff_id', v_appointment.staff_id,
    'amount', p_amount,
    'payment_method', v_method::text,
    'tip_amount', coalesce(p_tip_amount, 0),
    'tax_amount', coalesce(p_tax_amount, 0),
    'status', 'completed'
  );
end;
$$;

create function public.set_appointment_status(
  p_appointment_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_appointment public.appointments%rowtype;
  v_new_status public.appointment_status;
  v_is_operations boolean;
  v_is_assigned_staff boolean;
  v_allowed boolean := false;
begin
  if auth.uid() is null or not private.is_active_user() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  begin
    v_new_status := lower(btrim(p_status))::public.appointment_status;
  exception when invalid_text_representation then
    raise exception 'Invalid appointment status' using errcode = '22023';
  end;

  select * into v_appointment
    from public.appointments
   where id = p_appointment_id
   for update;
  if not found then
    raise exception 'Appointment not found' using errcode = 'P0002';
  end if;

  v_is_operations := private.is_operations();
  v_is_assigned_staff := v_appointment.staff_id = private.current_staff_id();
  if not v_is_operations and not v_is_assigned_staff then
    raise exception 'Not allowed to update this appointment' using errcode = '42501';
  end if;

  if v_appointment.status = v_new_status then
    v_allowed := true;
  elsif v_is_operations then
    v_allowed :=
      (v_appointment.status = 'pending' and v_new_status in ('booked', 'confirmed', 'declined', 'canceled'))
      or (v_appointment.status in ('booked', 'confirmed') and v_new_status in ('checked-in', 'in-service', 'in_progress', 'canceled', 'no-show'))
      or (v_appointment.status in ('checked-in', 'in-service') and v_new_status in ('in_progress', 'canceled'))
      or (v_appointment.status = 'in_progress' and v_new_status in ('completed', 'canceled'));
  else
    v_allowed :=
      (v_appointment.status = 'pending' and v_new_status in ('booked', 'declined'))
      or (v_appointment.status in ('booked', 'confirmed', 'checked-in', 'in-service') and v_new_status = 'in_progress')
      or (v_appointment.status = 'in_progress' and v_new_status = 'completed');
  end if;

  if not v_allowed then
    raise exception 'Invalid appointment status transition from % to %',
      v_appointment.status, v_new_status using errcode = '22023';
  end if;

  update public.appointments set status = v_new_status where id = p_appointment_id;

  return jsonb_build_object(
    'appointment_id', p_appointment_id,
    'status', v_new_status::text
  );
end;
$$;

create function public.cancel_appointment(p_appointment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_appointment public.appointments%rowtype;
begin
  if auth.uid() is null or not private.is_active_user() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_appointment
    from public.appointments
   where id = p_appointment_id
   for update;
  if not found then
    raise exception 'Appointment not found' using errcode = 'P0002';
  end if;

  if not private.is_operations()
     and v_appointment.customer_id <> private.current_customer_id() then
    raise exception 'Not allowed to cancel this appointment' using errcode = '42501';
  end if;

  if v_appointment.status not in ('pending', 'booked', 'confirmed') then
    raise exception 'This appointment can no longer be canceled' using errcode = '22023';
  end if;

  update public.appointments set status = 'canceled' where id = p_appointment_id;

  return jsonb_build_object(
    'appointment_id', p_appointment_id,
    'status', 'canceled'
  );
end;
$$;

create function public.update_appointment_notes(
  p_appointment_id uuid,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid;
begin
  if auth.uid() is null or not private.is_active_user() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select a.staff_id into v_staff_id
    from public.appointments as a
   where a.id = p_appointment_id
   for update;
  if not found then
    raise exception 'Appointment not found' using errcode = 'P0002';
  end if;

  if not private.is_operations() and v_staff_id <> private.current_staff_id() then
    raise exception 'Not allowed to update these notes' using errcode = '42501';
  end if;

  update public.appointments
     set notes = nullif(btrim(p_notes), '')
   where id = p_appointment_id;

  return jsonb_build_object(
    'appointment_id', p_appointment_id,
    'notes', nullif(btrim(p_notes), '')
  );
end;
$$;

create function public.refund_transaction(p_transaction_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status public.transaction_status;
begin
  if auth.uid() is null or not private.is_operations() then
    raise exception 'Not allowed to refund transactions' using errcode = '42501';
  end if;

  select t.status into v_status
    from public.transactions as t
   where t.id = p_transaction_id
   for update;
  if not found then
    raise exception 'Transaction not found' using errcode = 'P0002';
  end if;

  if v_status <> 'completed' then
    raise exception 'Only completed transactions can be refunded' using errcode = '22023';
  end if;

  update public.transactions set status = 'refunded' where id = p_transaction_id;
  return jsonb_build_object('transaction_id', p_transaction_id, 'status', 'refunded');
end;
$$;

create function public.get_dashboard_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Singapore')::date;
  v_result jsonb;
begin
  if auth.uid() is null or not private.is_operations() then
    raise exception 'Not allowed to view dashboard data' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'stats', jsonb_build_object(
      'today_bookings', (
        select count(*)::integer
          from public.appointments as a
         where (a.start_time at time zone 'Asia/Singapore')::date = v_today
           and a.status not in ('canceled', 'declined', 'no-show')
      ),
      'total_bookings', (
        select count(*)::integer
          from public.appointments as a
         where a.status not in ('canceled', 'declined')
      ),
      'total_barbers', (
        select count(*)::integer from public.staff as s where s.is_active
      ),
      'revenue_today', (
        select coalesce(sum(t.amount + t.tip_amount), 0)
          from public.transactions as t
         where (t.created_at at time zone 'Asia/Singapore')::date = v_today
           and t.status = 'completed'
      ),
      'pending_count', (
        select count(*)::integer
          from public.appointments as a
         where a.status = 'pending'
      )
    ),
    'analytics', (
      select jsonb_build_object(
        'days', jsonb_agg(to_char(d.day, 'Dy') order by d.day),
        'values', jsonb_agg(coalesce(x.booking_count, 0) order by d.day)
      )
      from generate_series(v_today - 6, v_today, interval '1 day') as d(day)
      left join lateral (
        select count(*)::integer as booking_count
          from public.appointments as a
         where (a.start_time at time zone 'Asia/Singapore')::date = d.day::date
           and a.status not in ('canceled', 'declined')
      ) as x on true
    ),
    'next_client', (
      select to_jsonb(n)
      from (
        select
          c.full_name as customer_name,
          to_char(a.start_time at time zone 'Asia/Singapore', 'FMMonth FMDD, YYYY') as date,
          to_char(a.start_time at time zone 'Asia/Singapore', 'FMHH12:MI AM') as time,
          to_char(a.end_time at time zone 'Asia/Singapore', 'FMHH12:MI AM') as end_time,
          sv.name::text as service,
          st.name as employee,
          a.status::text as status
        from public.appointments as a
        join public.customers as c on c.id = a.customer_id
        left join public.staff as st on st.id = a.staff_id
        left join public.services as sv on sv.id = a.service_id
        where a.start_time >= now()
          and a.status not in ('canceled', 'declined', 'no-show')
        order by a.start_time
        limit 1
      ) as n
    ),
    'recent_bookings', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.sort_time desc), '[]'::jsonb)
      from (
        select
          a.id as appointment_id,
          to_char(a.start_time at time zone 'Asia/Singapore', 'FMHH12:MI AM') as time,
          to_char(a.start_time at time zone 'Asia/Singapore', 'Mon DD, YYYY') as date_label,
          c.full_name as customer,
          coalesce(sv.name::text, 'N/A') as service,
          coalesce(sv.price, 0) as price,
          to_char(a.start_time at time zone 'Asia/Singapore', 'FMHH12:MI AM')
            || ' - ' ||
          to_char(a.end_time at time zone 'Asia/Singapore', 'FMHH12:MI AM') as schedule,
          coalesce(st.name, 'N/A') as employee,
          a.status::text as status,
          a.start_time as date,
          a.start_time as sort_time
        from public.appointments as a
        join public.customers as c on c.id = a.customer_id
        left join public.staff as st on st.id = a.staff_id
        left join public.services as sv on sv.id = a.service_id
        order by a.start_time desc
        limit 10
      ) as r
    ),
    'top_barbers', (
      select coalesce(jsonb_agg(to_jsonb(b) order by b.total_appointments desc, b.name), '[]'::jsonb)
      from (
        select
          st.id as staff_id,
          st.name,
          st.role,
          st.profile_photo,
          count(a.id)::integer as total_appointments
        from public.staff as st
        left join public.appointments as a
          on a.staff_id = st.id
         and a.status not in ('canceled', 'declined')
        where st.is_active
        group by st.id
        order by total_appointments desc, st.name
        limit 50
      ) as b
    ),
    'monthly_revenue', (
      select coalesce(jsonb_agg(to_jsonb(m) order by m.month_start), '[]'::jsonb)
      from (
        select
          d.month_start,
          to_char(d.month_start, 'Mon') as month,
          coalesce(sum(t.amount + t.tip_amount), 0) as revenue
        from generate_series(
          date_trunc('month', v_today::timestamp) - interval '5 months',
          date_trunc('month', v_today::timestamp),
          interval '1 month'
        ) as d(month_start)
        left join public.transactions as t
          on date_trunc('month', t.created_at at time zone 'Asia/Singapore') = d.month_start
         and t.status = 'completed'
        group by d.month_start
      ) as m
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.create_appointment(uuid, uuid, timestamptz, text) from public, anon;
revoke all on function public.reschedule_appointment(uuid, timestamptz, uuid) from public, anon;
revoke all on function public.complete_appointment(uuid, numeric, text, numeric, numeric) from public, anon;
revoke all on function public.set_appointment_status(uuid, text) from public, anon;
revoke all on function public.cancel_appointment(uuid) from public, anon;
revoke all on function public.update_appointment_notes(uuid, text) from public, anon;
revoke all on function public.refund_transaction(uuid) from public, anon;
revoke all on function public.get_dashboard_data() from public, anon;

grant execute on function public.create_appointment(uuid, uuid, timestamptz, text) to authenticated;
grant execute on function public.reschedule_appointment(uuid, timestamptz, uuid) to authenticated;
grant execute on function public.complete_appointment(uuid, numeric, text, numeric, numeric) to authenticated;
grant execute on function public.set_appointment_status(uuid, text) to authenticated;
grant execute on function public.cancel_appointment(uuid) to authenticated;
grant execute on function public.update_appointment_notes(uuid, text) to authenticated;
grant execute on function public.refund_transaction(uuid) to authenticated;
grant execute on function public.get_dashboard_data() to authenticated;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.derive_appointment_end_time() from public, anon, authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;

-- Explicit API grants. RLS remains the authorization boundary.
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.customers from anon, authenticated;
revoke all on table public.service_categories from anon, authenticated;
revoke all on table public.services from anon, authenticated;
revoke all on table public.staff from anon, authenticated;
revoke all on table public.appointments from anon, authenticated;
revoke all on table public.transactions from anon, authenticated;
revoke all on table public.feedback from anon, authenticated;

grant select, update on table public.profiles to authenticated;
grant select, insert, update, delete on table public.customers to authenticated;
grant select on table public.service_categories, public.services to anon, authenticated;
grant insert, update, delete on table public.service_categories, public.services to authenticated;
grant select, insert, update, delete on table public.staff to authenticated;
grant select, insert, update, delete on table public.appointments to authenticated;
grant select, insert, update, delete on table public.transactions to authenticated;
grant select, insert, update, delete on table public.feedback to authenticated;

grant select on table public.service_catalog, public.category_catalog, public.staff_directory to anon, authenticated;
grant select on table public.appointment_details, public.transaction_details to authenticated;

-- Storage buckets. Customer avatars are private; staff/service images are public.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'customer-avatars',
    'customer-avatars',
    false,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
  ),
  (
    'staff-avatars',
    'staff-avatars',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
  ),
  (
    'service-images',
    'service-images',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
  )
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy customer_avatars_read_visible
on storage.objects for select to authenticated
using (
  bucket_id = 'customer-avatars'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and private.can_view_customer(((storage.foldername(name))[1])::uuid)
);

create policy customer_avatars_insert_owner_or_management
on storage.objects for insert to authenticated
with check (
  bucket_id = 'customer-avatars'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    ((storage.foldername(name))[1])::uuid = private.current_customer_id()
    or private.is_management()
  )
);

create policy customer_avatars_update_owner_or_management
on storage.objects for update to authenticated
using (
  bucket_id = 'customer-avatars'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    ((storage.foldername(name))[1])::uuid = private.current_customer_id()
    or private.is_management()
  )
)
with check (
  bucket_id = 'customer-avatars'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    ((storage.foldername(name))[1])::uuid = private.current_customer_id()
    or private.is_management()
  )
);

create policy customer_avatars_delete_owner_or_management
on storage.objects for delete to authenticated
using (
  bucket_id = 'customer-avatars'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    ((storage.foldername(name))[1])::uuid = private.current_customer_id()
    or private.is_management()
  )
);

create policy public_image_buckets_read
on storage.objects for select to anon, authenticated
using (bucket_id in ('staff-avatars', 'service-images'));

create policy staff_avatars_insert_owner_or_management
on storage.objects for insert to authenticated
with check (
  bucket_id = 'staff-avatars'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    ((storage.foldername(name))[1])::uuid = private.current_staff_id()
    or private.is_management()
  )
);

create policy staff_avatars_update_owner_or_management
on storage.objects for update to authenticated
using (
  bucket_id = 'staff-avatars'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    ((storage.foldername(name))[1])::uuid = private.current_staff_id()
    or private.is_management()
  )
)
with check (
  bucket_id = 'staff-avatars'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    ((storage.foldername(name))[1])::uuid = private.current_staff_id()
    or private.is_management()
  )
);

create policy staff_avatars_delete_owner_or_management
on storage.objects for delete to authenticated
using (
  bucket_id = 'staff-avatars'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    ((storage.foldername(name))[1])::uuid = private.current_staff_id()
    or private.is_management()
  )
);

create policy service_images_insert_management
on storage.objects for insert to authenticated
with check (bucket_id = 'service-images' and private.is_management());

create policy service_images_update_management
on storage.objects for update to authenticated
using (bucket_id = 'service-images' and private.is_management())
with check (bucket_id = 'service-images' and private.is_management());

create policy service_images_delete_management
on storage.objects for delete to authenticated
using (bucket_id = 'service-images' and private.is_management());

commit;
