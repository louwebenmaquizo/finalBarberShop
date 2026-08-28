-- Hide internal account and cost fields from the anonymous/customer catalog.
-- Management users retain the full view shape expected by the admin UI.
begin;

create or replace view public.service_catalog
with (security_invoker = true)
as
select
  s.id as service_id,
  s.name,
  s.category_id,
  c.name as category_name,
  s.duration_minutes,
  s.price,
  (case when private.is_management() then s.cost end)::numeric(10, 2) as cost,
  s.description,
  s.image_url,
  s.is_active,
  s.created_at,
  s.updated_at
from public.services as s
left join public.service_categories as c on c.id = s.category_id;

create or replace function private.staff_directory_rows()
returns table (
  staff_id uuid,
  user_id uuid,
  username extensions.citext,
  name text,
  phone text,
  email extensions.citext,
  role text,
  skills text,
  pay_rate numeric,
  commission_rate numeric,
  profile_photo text,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    s.id,
    case when private.is_management() or s.user_id = auth.uid() then s.user_id end,
    case when private.is_management() or s.user_id = auth.uid() then p.username end,
    s.name,
    case when private.is_management() or s.user_id = auth.uid() then s.phone end,
    case when private.is_management() or s.user_id = auth.uid() then s.email end,
    s.role,
    s.skills,
    case when private.is_management() or s.user_id = auth.uid() then s.pay_rate end,
    case when private.is_management() or s.user_id = auth.uid() then s.commission_rate end,
    s.profile_photo,
    s.is_active,
    s.created_at,
    s.updated_at
  from public.staff as s
  left join public.profiles as p on p.id = s.user_id
  where s.is_active or private.is_management() or s.user_id = auth.uid();
$$;

revoke all on function private.staff_directory_rows() from public;
grant execute on function private.staff_directory_rows() to anon, authenticated;

commit;
