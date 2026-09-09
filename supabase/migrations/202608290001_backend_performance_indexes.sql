-- High Performance Backend Indices for Liem Barber Shop
-- Speeds up appointment overlap queries, catalog listing, staff filtering, and customer lookups

-- 1. Fast Appointment Overlap & Conflict Queries
create index if not exists idx_appointments_staff_time_status 
  on public.appointments (staff_id, end_time, start_time, status);

create index if not exists idx_appointments_customer_active
  on public.appointments (customer_id, status, start_time desc);

-- 2. Fast Catalog Services & Category Queries
create index if not exists idx_services_active_category 
  on public.services (is_active, category_id, name);

-- 3. Fast Active Barbers / Staff Queries
create index if not exists idx_staff_active_role 
  on public.staff (is_active, role, name);

-- 4. Fast Customer Profile & Auth Lookups
create index if not exists idx_customers_user_id 
  on public.customers (user_id);

create index if not exists idx_customers_phone_email 
  on public.customers (phone, email);

-- 5. Fast Profiles Role Check
create index if not exists idx_profiles_role_active 
  on public.profiles (role, is_active);
