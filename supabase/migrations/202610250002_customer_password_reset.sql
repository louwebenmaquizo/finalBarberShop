-- ============================================================================
-- 1. admin_reset_customer_password: lets an admin/manager set a new password
--    for a customer who forgot theirs (the app has no password-reset email).
--    Only customer accounts can be reset this way, never staff or admins.
-- 2. reschedule_appointment: customers may not move a booking more than 90
--    days ahead (same rule as create_appointment).
-- ============================================================================

begin;

create or replace function public.admin_reset_customer_password(
  p_email text,
  p_new_password text
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_role public.app_role;
begin
  if auth.uid() is null or not coalesce(private.is_management(), false) then
    return json_build_object('success', false,
      'message', 'Only admins and managers can reset customer passwords');
  end if;

  if length(coalesce(p_new_password, '')) < 8 then
    return json_build_object('success', false,
      'message', 'Password must be at least 8 characters long');
  end if;

  select u.id into v_user_id
    from auth.users as u
   where lower(u.email) = lower(btrim(coalesce(p_email, '')));
  if v_user_id is null then
    return json_build_object('success', false,
      'message', 'No account uses that email address');
  end if;

  select p.role into v_role from public.profiles as p where p.id = v_user_id;
  if v_role is distinct from 'customer' then
    return json_build_object('success', false,
      'message', 'That account is not a customer. Staff passwords are changed in the Employee screen.');
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
         updated_at = now()
   where id = v_user_id;

  return json_build_object('success', true, 'message', 'Password reset');
end;
$$;

revoke all on function public.admin_reset_customer_password(text, text) from public, anon;
grant execute on function public.admin_reset_customer_password(text, text) to authenticated;

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

  -- Customers get the same booking window as create_appointment.
  if not v_is_operations and p_start_time > now() + interval '90 days' then
    raise exception 'Appointments can be booked at most 90 days ahead' using errcode = '22023';
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

revoke all on function public.reschedule_appointment(uuid, timestamptz, uuid) from public, anon;
grant execute on function public.reschedule_appointment(uuid, timestamptz, uuid) to authenticated;

commit;
