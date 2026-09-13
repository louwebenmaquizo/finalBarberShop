-- ============================================================================
-- Migration: Admin Staff Management & Password Update RPC (Hardened)
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

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

  -- 1. Check if existing user_id is actually valid in auth.users
  if v_user_id is not null then
    if not exists (select 1 from auth.users where id = v_user_id) then
      v_user_id := null; -- Reset orphaned dummy ID
    end if;
  end if;

  -- 2. If user_id not found in auth.users, try looking up by email
  if v_user_id is null and v_staff_email is not null and v_staff_email <> '' then
    select id into v_user_id
    from auth.users
    where lower(email) = lower(v_staff_email);
  end if;

  -- 3. If still null, create the user in auth.users
  if v_user_id is null then
    if v_staff_email is null or v_staff_email = '' then
      v_staff_email := lower(regexp_replace(v_staff_name, '[^a-zA-Z0-9]', '', 'g')) || '@liembarber.com';
    end if;

    v_user_id := gen_random_uuid();
    insert into auth.users (
      id, instance_id, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role
    )
    values (
      v_user_id, '00000000-0000-0000-0000-000000000000'::uuid, v_staff_email,
      extensions.crypt(p_new_password, extensions.gen_salt('bf')), now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      json_build_object('username', split_part(v_staff_email, '@', 1), 'name', v_staff_name)::jsonb,
      false, 'authenticated'
    );
  else
    -- User exists in auth.users -> update their password
    update auth.users
    set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = v_user_id;
  end if;

  -- 4. Ensure profile is updated to 'barber'
  insert into public.profiles (id, username, role, is_active)
  values (v_user_id, split_part(v_staff_email, '@', 1), 'barber', true)
  on conflict (id) do update
  set role = 'barber', is_active = true, updated_at = now();

  -- 5. Link staff record to the confirmed user_id
  update public.staff
  set user_id = v_user_id,
      email = v_staff_email
  where id = p_staff_id;

  return json_build_object(
    'success', true,
    'message', 'Staff password updated and synced in database',
    'user_id', v_user_id,
    'email', v_staff_email
  );
exception when others then
  return json_build_object(
    'success', false,
    'message', SQLERRM
  );
end;
$$;

grant execute on function public.admin_update_staff_password(uuid, text) to authenticated, anon;
