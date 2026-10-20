-- ============================================================================
-- Security hardening (pre-launch audit, 2026-10-17)
--
-- 1. admin_update_staff_password: require admin/manager, never callable by
--    anon, and never take over admin/manager/cashier/customer accounts.
-- 2. Appointment RPCs: authorization checks compared against NULL helper
--    results (e.g. a customer has no staff id), and `if null` is treated as
--    false in PL/pgSQL, so the checks were silently skipped. Every check now
--    uses coalesce(..., false).
-- 3. create_appointment: cap active upcoming bookings per customer and how
--    far ahead a customer may book.
-- 4. get_staff_busy_intervals: lets customers see when a barber is busy
--    without exposing who booked.
-- 5. ai_usage: server-side rate limiting for the ai-chat Edge Function.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Staff password management
-- ---------------------------------------------------------------------------
create or replace function public.admin_update_staff_password(
  p_staff_id uuid,
  p_new_password text
)
returns json
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_staff_name text;
  v_staff_email text;
  v_existing_role public.app_role;
begin
  if auth.uid() is null or not coalesce(private.is_management(), false) then
    return json_build_object(
      'success', false,
      'message', 'Only admins and managers can change staff passwords'
    );
  end if;

  if length(coalesce(p_new_password, '')) < 8 then
    return json_build_object(
      'success', false,
      'message', 'Password must be at least 8 characters long'
    );
  end if;

  select user_id, name, email
    into v_user_id, v_staff_name, v_staff_email
    from public.staff
   where id = p_staff_id;

  if not found then
    return json_build_object('success', false, 'message', 'Staff record not found');
  end if;

  -- Reset an orphaned user id that no longer exists in auth.users.
  if v_user_id is not null
     and not exists (select 1 from auth.users where id = v_user_id) then
    v_user_id := null;
  end if;

  if v_user_id is null and coalesce(v_staff_email, '') <> '' then
    select id into v_user_id
      from auth.users
     where lower(email) = lower(v_staff_email);
  end if;

  -- Only barber/staff accounts (or accounts with no profile yet) may be
  -- managed here. This blocks resetting an admin's or a customer's password
  -- by pointing a staff row at their user id or email.
  if v_user_id is not null then
    select role into v_existing_role from public.profiles where id = v_user_id;
    if v_existing_role is not null and v_existing_role not in ('barber', 'staff') then
      return json_build_object(
        'success', false,
        'message', 'That email belongs to a non-staff account and cannot be managed here'
      );
    end if;
  end if;

  if v_user_id is null then
    if coalesce(v_staff_email, '') = '' then
      v_staff_email := lower(regexp_replace(v_staff_name, '[^a-zA-Z0-9]', '', 'g')) || '@liembarber.com';
    end if;

    v_user_id := gen_random_uuid();
    -- Token columns must be '' (not NULL) or Supabase Auth fails to sign the
    -- user in ("converting NULL to string is unsupported").
    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin,
      confirmation_token, recovery_token, email_change_token_new, email_change
    )
    values (
      v_user_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
      v_staff_email, extensions.crypt(p_new_password, extensions.gen_salt('bf')), now(),
      now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('username', split_part(v_staff_email, '@', 1), 'name', v_staff_name),
      false, '', '', '', ''
    );
  else
    update auth.users
       set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_user_id;
  end if;

  insert into public.profiles (id, username, role, is_active)
  values (v_user_id, split_part(v_staff_email, '@', 1), 'barber', true)
  on conflict (id) do update
  set role = 'barber', is_active = true, updated_at = now();

  update public.staff
     set user_id = v_user_id,
         email = v_staff_email
   where id = p_staff_id;

  return json_build_object(
    'success', true,
    'message', 'Staff password updated',
    'user_id', v_user_id,
    'email', v_staff_email
  );
exception when others then
  return json_build_object('success', false, 'message', SQLERRM);
end;
$$;

revoke all on function public.admin_update_staff_password(uuid, text) from public, anon;
grant execute on function public.admin_update_staff_password(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Appointment RPCs with NULL-safe authorization
-- ---------------------------------------------------------------------------
create or replace function public.create_appointment(
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
  -- Edit these two limits to match the shop's booking policy.
  c_max_active_bookings constant integer := 3;
  c_max_days_ahead constant integer := 90;
  v_customer_id uuid;
  v_duration integer;
  v_appointment_id uuid;
  v_end_time timestamptz;
  v_active_count integer;
begin
  if auth.uid() is null or not coalesce(private.is_active_user(), false) then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  v_customer_id := private.current_customer_id();
  if v_customer_id is null then
    raise exception 'Customer profile not found' using errcode = '42501';
  end if;

  if p_start_time is null or p_start_time <= now() then
    raise exception 'Appointment time must be in the future' using errcode = '22023';
  end if;

  if p_start_time > now() + make_interval(days => c_max_days_ahead) then
    raise exception 'Appointments can be booked at most % days ahead', c_max_days_ahead
      using errcode = '22023';
  end if;

  -- Serialize concurrent bookings by the same customer so the cap holds.
  perform 1 from public.customers where id = v_customer_id for update;

  select count(*) into v_active_count
    from public.appointments as a
   where a.customer_id = v_customer_id
     and a.start_time > now()
     and a.status in ('pending', 'booked', 'confirmed');
  if v_active_count >= c_max_active_bookings then
    raise exception 'You already have % upcoming appointments. Please cancel one before booking another.',
      v_active_count using errcode = '22023';
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
    customer_id, staff_id, service_id, start_time, end_time, status, source, notes
  )
  values (
    v_customer_id, p_staff_id, p_service_id, p_start_time, v_end_time,
    'pending', 'web', left(nullif(btrim(p_notes), ''), 1000)
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

create or replace function public.reschedule_appointment(
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
  v_is_operations boolean;
  v_customer_owned boolean;
begin
  if auth.uid() is null or not coalesce(private.is_active_user(), false) then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_appointment
    from public.appointments
   where id = p_appointment_id
   for update;
  if not found then
    raise exception 'Appointment not found' using errcode = 'P0002';
  end if;

  v_is_operations := coalesce(private.is_operations(), false);
  v_customer_owned := coalesce(v_appointment.customer_id = private.current_customer_id(), false);
  if not v_is_operations and not v_customer_owned then
    raise exception 'Not allowed to reschedule this appointment' using errcode = '42501';
  end if;

  if v_customer_owned and not v_is_operations
     and v_appointment.status not in ('pending', 'booked', 'confirmed') then
    raise exception 'This appointment can no longer be rescheduled' using errcode = '22023';
  end if;

  if p_start_time is null or p_start_time <= now() then
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

create or replace function public.complete_appointment(
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
  if auth.uid() is null or not coalesce(private.is_active_user(), false) then
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

  v_authorized := coalesce(private.is_operations(), false)
    or coalesce(v_appointment.staff_id = private.current_staff_id(), false);
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

  update public.appointments set status = 'completed' where id = p_appointment_id;

  insert into public.transactions (
    appointment_id, customer_id, amount, payment_method, tip_amount, tax_amount, staff_id, status
  )
  values (
    p_appointment_id, v_appointment.customer_id, p_amount, v_method,
    coalesce(p_tip_amount, 0), coalesce(p_tax_amount, 0), v_appointment.staff_id, 'completed'
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

create or replace function public.set_appointment_status(
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
  if auth.uid() is null or not coalesce(private.is_active_user(), false) then
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

  v_is_operations := coalesce(private.is_operations(), false);
  v_is_assigned_staff := coalesce(v_appointment.staff_id = private.current_staff_id(), false);
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

  return jsonb_build_object('appointment_id', p_appointment_id, 'status', v_new_status::text);
end;
$$;

create or replace function public.cancel_appointment(p_appointment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_appointment public.appointments%rowtype;
begin
  if auth.uid() is null or not coalesce(private.is_active_user(), false) then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_appointment
    from public.appointments
   where id = p_appointment_id
   for update;
  if not found then
    raise exception 'Appointment not found' using errcode = 'P0002';
  end if;

  if not coalesce(private.is_operations(), false)
     and not coalesce(v_appointment.customer_id = private.current_customer_id(), false) then
    raise exception 'Not allowed to cancel this appointment' using errcode = '42501';
  end if;

  if v_appointment.status not in ('pending', 'booked', 'confirmed') then
    raise exception 'This appointment can no longer be canceled' using errcode = '22023';
  end if;

  update public.appointments set status = 'canceled' where id = p_appointment_id;

  return jsonb_build_object('appointment_id', p_appointment_id, 'status', 'canceled');
end;
$$;

create or replace function public.update_appointment_notes(
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
  if auth.uid() is null or not coalesce(private.is_active_user(), false) then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select a.staff_id into v_staff_id
    from public.appointments as a
   where a.id = p_appointment_id
   for update;
  if not found then
    raise exception 'Appointment not found' using errcode = 'P0002';
  end if;

  if not coalesce(private.is_operations(), false)
     and not coalesce(v_staff_id = private.current_staff_id(), false) then
    raise exception 'Not allowed to update these notes' using errcode = '42501';
  end if;

  update public.appointments
     set notes = left(nullif(btrim(p_notes), ''), 1000)
   where id = p_appointment_id;

  return jsonb_build_object(
    'appointment_id', p_appointment_id,
    'notes', left(nullif(btrim(p_notes), ''), 1000)
  );
end;
$$;

revoke all on function public.create_appointment(uuid, uuid, timestamptz, text) from public, anon;
revoke all on function public.reschedule_appointment(uuid, timestamptz, uuid) from public, anon;
revoke all on function public.complete_appointment(uuid, numeric, text, numeric, numeric) from public, anon;
revoke all on function public.set_appointment_status(uuid, text) from public, anon;
revoke all on function public.cancel_appointment(uuid) from public, anon;
revoke all on function public.update_appointment_notes(uuid, text) from public, anon;
grant execute on function public.create_appointment(uuid, uuid, timestamptz, text) to authenticated;
grant execute on function public.reschedule_appointment(uuid, timestamptz, uuid) to authenticated;
grant execute on function public.complete_appointment(uuid, numeric, text, numeric, numeric) to authenticated;
grant execute on function public.set_appointment_status(uuid, text) to authenticated;
grant execute on function public.cancel_appointment(uuid) to authenticated;
grant execute on function public.update_appointment_notes(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Barber availability without exposing other customers' bookings
-- ---------------------------------------------------------------------------
create or replace function public.get_staff_busy_intervals(
  p_staff_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table (appointment_id uuid, start_time timestamptz, end_time timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select
    case when private.can_view_appointment(a.id) then a.id end,
    a.start_time,
    a.end_time
  from public.appointments as a
  where auth.uid() is not null
    and a.staff_id = p_staff_id
    and a.start_time < p_to
    and a.end_time > p_from
    and p_to - p_from <= interval '8 days'
    and a.status not in ('canceled', 'declined', 'no-show')
  order by a.start_time;
$$;

revoke all on function public.get_staff_busy_intervals(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.get_staff_busy_intervals(uuid, timestamptz, timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. AI usage log for server-side rate limiting (written by Edge Functions)
-- ---------------------------------------------------------------------------
create table if not exists public.ai_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists ai_usage_user_created_idx
  on public.ai_usage (user_id, created_at desc);

alter table public.ai_usage enable row level security;
revoke all on table public.ai_usage from anon, authenticated;

commit;
