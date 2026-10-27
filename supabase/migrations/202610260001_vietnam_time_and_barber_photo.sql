-- ============================================================================
-- Vietnam localisation + barber self-service
--
-- 1. Dates/times shown in the app and "today" on the dashboard use Vietnam
--    time (Asia/Ho_Chi_Minh, UTC+7) instead of Asia/Singapore (UTC+8).
-- 2. update_my_staff_photo: a barber may set their OWN profile photo. Staff
--    rows are otherwise admin/manager-only, so this changes nothing else.
-- ============================================================================

begin;

create or replace function private.appointment_detail_rows()
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
    (a.start_time at time zone 'Asia/Ho_Chi_Minh')::date,
    (a.start_time at time zone 'Asia/Ho_Chi_Minh')::time
  from public.appointments as a
  join public.customers as c on c.id = a.customer_id
  left join public.staff as st on st.id = a.staff_id
  left join public.services as sv on sv.id = a.service_id
  left join public.service_categories as sc on sc.id = sv.category_id
  where private.can_view_appointment(a.id);
$$;

create or replace function public.get_dashboard_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
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
         where (a.start_time at time zone 'Asia/Ho_Chi_Minh')::date = v_today
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
         where (t.created_at at time zone 'Asia/Ho_Chi_Minh')::date = v_today
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
         where (a.start_time at time zone 'Asia/Ho_Chi_Minh')::date = d.day::date
           and a.status not in ('canceled', 'declined')
      ) as x on true
    ),
    'next_client', (
      select to_jsonb(n)
      from (
        select
          c.full_name as customer_name,
          to_char(a.start_time at time zone 'Asia/Ho_Chi_Minh', 'FMMonth FMDD, YYYY') as date,
          to_char(a.start_time at time zone 'Asia/Ho_Chi_Minh', 'FMHH12:MI AM') as time,
          to_char(a.end_time at time zone 'Asia/Ho_Chi_Minh', 'FMHH12:MI AM') as end_time,
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
          to_char(a.start_time at time zone 'Asia/Ho_Chi_Minh', 'FMHH12:MI AM') as time,
          to_char(a.start_time at time zone 'Asia/Ho_Chi_Minh', 'Mon DD, YYYY') as date_label,
          c.full_name as customer,
          coalesce(sv.name::text, 'N/A') as service,
          coalesce(sv.price, 0) as price,
          to_char(a.start_time at time zone 'Asia/Ho_Chi_Minh', 'FMHH12:MI AM')
            || ' - ' ||
          to_char(a.end_time at time zone 'Asia/Ho_Chi_Minh', 'FMHH12:MI AM') as schedule,
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
          on date_trunc('month', t.created_at at time zone 'Asia/Ho_Chi_Minh') = d.month_start
         and t.status = 'completed'
        group by d.month_start
      ) as m
    )
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.update_my_staff_photo(p_path text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff_id uuid;
begin
  v_staff_id := private.current_staff_id();
  if auth.uid() is null or v_staff_id is null then
    raise exception 'Only active barbers can update their photo' using errcode = '42501';
  end if;

  -- The file must be inside the barber's own folder in staff-avatars.
  if p_path is null
     or position(v_staff_id::text || '/' in p_path) <> 1
     or p_path like '%..%' then
    raise exception 'Invalid photo path' using errcode = '22023';
  end if;

  update public.staff set profile_photo = p_path where id = v_staff_id;

  return jsonb_build_object('staff_id', v_staff_id, 'profile_photo', p_path);
end;
$$;

revoke all on function public.update_my_staff_photo(text) from public, anon;
grant execute on function public.update_my_staff_photo(text) to authenticated;

commit;
