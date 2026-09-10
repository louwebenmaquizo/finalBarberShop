-- ============================================================================
-- Promote Admin User Account
-- Ensures admin@barbershop.com has the 'admin' role in public.profiles
-- ============================================================================

begin;

update public.profiles
set role = 'admin',
    is_active = true
where id in (
  select id from auth.users where lower(email) in ('admin@barbershop.com')
);

delete from public.customers
where user_id in (
  select id from auth.users where lower(email) in ('admin@barbershop.com')
);

commit;
