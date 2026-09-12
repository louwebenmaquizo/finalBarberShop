-- Allow authenticated customers to create their own customer record during setup
drop policy if exists customers_insert_management on public.customers;

create policy customers_insert_owner_or_management
on public.customers for insert to authenticated
with check (user_id = auth.uid() or private.is_management());
