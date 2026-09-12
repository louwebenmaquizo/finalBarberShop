-- ============================================================================
-- Check Email Registered RPC
-- Safe function for client to determine if an email is already registered
-- ============================================================================

create or replace function public.check_email_registered(p_email text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_normalized text;
begin
  if p_email is null or btrim(p_email) = '' then
    return false;
  end if;

  v_normalized := lower(btrim(p_email));

  return exists (
    select 1
    from auth.users
    where lower(email) = v_normalized
  );
end;
$$;

revoke all on function public.check_email_registered(text) from public;
grant execute on function public.check_email_registered(text) to anon, authenticated;
