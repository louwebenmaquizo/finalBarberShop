-- ============================================================================
-- Migration: Admin Staff Management & Password Update RPC
-- Enables administrators to directly update staff login passwords and create
-- staff accounts in auth.users without external service-role dependency.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ============================================================================
-- 1. admin_update_staff_password
-- ============================================================================
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
begin
  -- Validate password
  if length(coalesce(p_new_password, '')) < 8 then
    return json_build_object(
      'success', false,
      'message', 'Password must be at least 8 characters long'
    );
  end if;

  -- Get staff record
  select user_id, name, email
  into v_user_id, v_staff_name, v_staff_email
  from public.staff
  where id = p_staff_id;

  if not found then
    return json_build_object(
      'success', false,
      'message', 'Staff record not found'
    );
  end if;

  -- Case A: Staff already linked to auth.users -> Update password directly
  if v_user_id is not null then
    update auth.users
    set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = v_user_id;

    -- Ensure profile role is 'barber'
    update public.profiles
    set role = 'barber',
        is_active = true,
        updated_at = now()
    where id = v_user_id;

    return json_build_object(
      'success', true,
      'message', 'Password successfully updated in database for ' || coalesce(v_staff_name, 'staff member'),
      'user_id', v_user_id
    );
  else
    -- Case B: Staff not linked yet -> Create/link auth user and set password
    if v_staff_email is null or v_staff_email = '' then
      v_staff_email := lower(regexp_replace(v_staff_name, '[^a-zA-Z0-9]', '', 'g')) || '@liembarber.com';
    end if;

    select id into v_user_id
    from auth.users
    where lower(email) = lower(v_staff_email);

    if v_user_id is not null then
      update auth.users
      set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
          email_confirmed_at = coalesce(email_confirmed_at, now()),
          updated_at = now()
      where id = v_user_id;
    else
      v_user_id := gen_random_uuid();
      insert into auth.users (
        id,
        instance_id,
        email,
        encrypted_password,
        email_confirmed_at,
        created_at,
        updated_at,
        raw_app_meta_data,
        raw_user_meta_data,
        is_super_admin,
        role
      )
      values (
        v_user_id,
        '00000000-0000-0000-0000-000000000000'::uuid,
        v_staff_email,
        extensions.crypt(p_new_password, extensions.gen_salt('bf')),
        now(),
        now(),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        json_build_object('username', split_part(v_staff_email, '@', 1), 'name', v_staff_name)::jsonb,
        false,
        'authenticated'
      );
    end if;

    -- Upsert profile
    insert into public.profiles (id, username, role, is_active)
    values (v_user_id, split_part(v_staff_email, '@', 1), 'barber', true)
    on conflict (id) do update
    set role = 'barber', is_active = true, updated_at = now();

    -- Link staff record
    update public.staff
    set user_id = v_user_id,
        email = v_staff_email
    where id = p_staff_id;

    return json_build_object(
      'success', true,
      'message', 'Created login account and set password successfully',
      'user_id', v_user_id,
      'email', v_staff_email
    );
  end if;
exception when others then
  return json_build_object(
    'success', false,
    'message', SQLERRM
  );
end;
$$;

grant execute on function public.admin_update_staff_password(uuid, text) to authenticated, anon;

-- ============================================================================
-- 2. admin_create_staff_account
-- ============================================================================
create or replace function public.admin_create_staff_account(
  p_name text,
  p_email text,
  p_password text,
  p_phone text default null,
  p_role text default 'Barber',
  p_skills text default null,
  p_pay_rate numeric default null,
  p_commission_rate numeric default 0,
  p_profile_photo text default null
)
returns json
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_staff_id uuid;
  v_clean_email text;
  v_username text;
begin
  if length(coalesce(p_password, '')) < 8 then
    return json_build_object(
      'success', false,
      'message', 'Password must be at least 8 characters long'
    );
  end if;

  v_clean_email := lower(trim(p_email));
  if v_clean_email not like '%@%' then
    v_clean_email := lower(regexp_replace(p_name, '[^a-zA-Z0-9]', '', 'g')) || '@liembarber.com';
  end if;

  v_username := split_part(v_clean_email, '@', 1);

  -- Check if user exists in auth.users
  select id into v_user_id from auth.users where lower(email) = v_clean_email;

  if v_user_id is not null then
    update auth.users
    set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = v_user_id;
  else
    v_user_id := gen_random_uuid();
    insert into auth.users (
      id,
      instance_id,
      email,
      encrypted_password,
      email_confirmed_at,
      created_at,
      updated_at,
      raw_app_meta_data,
      raw_user_meta_data,
      is_super_admin,
      role
    )
    values (
      v_user_id,
      '00000000-0000-0000-0000-000000000000'::uuid,
      v_clean_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')),
      now(),
      now(),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      json_build_object('username', v_username, 'name', p_name)::jsonb,
      false,
      'authenticated'
    );
  end if;

  -- Upsert profile
  insert into public.profiles (id, username, role, is_active)
  values (v_user_id, v_username, 'barber', true)
  on conflict (id) do update
  set role = 'barber', is_active = true, updated_at = now();

  -- Insert staff record
  insert into public.staff (
    user_id,
    name,
    phone,
    email,
    role,
    skills,
    pay_rate,
    commission_rate,
    profile_photo,
    is_active
  )
  values (
    v_user_id,
    p_name,
    p_phone,
    v_clean_email,
    coalesce(p_role, 'Barber'),
    p_skills,
    p_pay_rate,
    coalesce(p_commission_rate, 0),
    p_profile_photo,
    true
  )
  returning id into v_staff_id;

  return json_build_object(
    'success', true,
    'message', 'Staff account and login credentials created',
    'staff_id', v_staff_id,
    'user_id', v_user_id,
    'email', v_clean_email
  );
exception when others then
  return json_build_object(
    'success', false,
    'message', SQLERRM
  );
end;
$$;

grant execute on function public.admin_create_staff_account to authenticated, anon;
