-- Safe starter catalog. No users, passwords, or private customer data.
insert into public.service_categories (name, description)
values
  ('Haircut', 'Precision cuts for adults and children.'),
  ('Styling', 'Finishing and styling services.'),
  ('Beard', 'Beard trimming, shaping, and grooming.')
on conflict (name) do update
set description = excluded.description;

insert into public.services (
  name,
  category_id,
  duration_minutes,
  price,
  cost,
  description,
  is_active
)
values
  (
    'Classic Haircut',
    (select id from public.service_categories where name = 'Haircut'),
    30,
    20.00,
    0,
    'A clean, classic cut finished to your preferred style.',
    true
  ),
  (
    'Skin Fade',
    (select id from public.service_categories where name = 'Haircut'),
    45,
    25.00,
    0,
    'A precise skin fade with a blended finish.',
    true
  ),
  (
    'Kids Haircut',
    (select id from public.service_categories where name = 'Haircut'),
    30,
    15.00,
    0,
    'A comfortable haircut service for children.',
    true
  ),
  (
    'Hair Styling',
    (select id from public.service_categories where name = 'Styling'),
    30,
    18.00,
    0,
    'Wash, dry, and style for a polished finish.',
    true
  ),
  (
    'Beard Grooming',
    (select id from public.service_categories where name = 'Beard'),
    30,
    15.00,
    0,
    'Beard trim, shaping, and finishing treatment.',
    true
  ),
  (
    'Haircut and Beard',
    (select id from public.service_categories where name = 'Haircut'),
    60,
    32.00,
    0,
    'A complete haircut and beard-grooming package.',
    true
  )
on conflict (name) do update
set category_id = excluded.category_id,
    duration_minutes = excluded.duration_minutes,
    price = excluded.price,
    cost = excluded.cost,
    description = excluded.description,
    is_active = excluded.is_active;
