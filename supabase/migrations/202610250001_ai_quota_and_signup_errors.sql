-- ============================================================================
-- 1. ai_take_quota: atomic per-user rate limit for the ai-chat Edge Function.
--    The previous check (count, then insert) let simultaneous requests all
--    pass; a per-user advisory lock now makes check-and-record one step.
-- 2. handle_new_auth_user: friendly error for invalid name/phone lengths.
-- ============================================================================

begin;

create or replace function public.ai_take_quota(
  p_user_id uuid,
  p_per_minute integer,
  p_per_day integer
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_minute integer;
  v_day integer;
begin
  -- Serialize concurrent requests from the same user.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  delete from public.ai_usage
   where user_id = p_user_id
     and created_at < now() - interval '2 days';

  select count(*) filter (where created_at >= now() - interval '1 minute'),
         count(*)
    into v_minute, v_day
    from public.ai_usage
   where user_id = p_user_id
     and created_at >= now() - interval '1 day';

  if v_minute >= p_per_minute then
    return 'minute';
  end if;
  if v_day >= p_per_day then
    return 'day';
  end if;

  insert into public.ai_usage (user_id) values (p_user_id);
  return 'ok';
end;
$$;

revoke all on function public.ai_take_quota(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.ai_take_quota(uuid, integer, integer) to service_role;

create or replace function public.handle_new_auth_user()
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
  -- Name or phone outside the allowed length: return a readable message
  -- instead of the raw constraint error (which exposed table internals).
  when check_violation then
    raise exception 'Please check your name (1-100 characters) and phone number (3-32 characters)'
      using errcode = '23514';
end;
$$;

commit;
