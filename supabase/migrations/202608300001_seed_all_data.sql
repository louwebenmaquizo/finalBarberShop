-- ============================================================================
-- Complete System Seeder Migration for Liem Barber Shop
-- Populates:
--   1. Service Categories (5 categories)
--   2. Services Catalog (12 services across categories)
--   3. Staff / Barbers (5 barbers with roles, rates, and skills)
--   4. Customers (8 customers with profiles, contact info, and notes)
--   5. Appointments (15 appointments: past, today, future, non-overlapping)
--   6. Transactions (Historical, recent, and today's transactions with tips/tax)
--   7. Customer Feedback / Reviews (Ratings 1-5 and authentic comments)
--
-- Safe and idempotent: Uses fixed deterministic UUIDs and ON CONFLICT DO UPDATE.
-- Timestamps are dynamically calculated relative to current date (Asia/Singapore).
-- ============================================================================

begin;

-- ============================================================================
-- 1. SERVICE CATEGORIES
-- ============================================================================
insert into public.service_categories (id, name, description)
values
  (
    'c0000000-0000-0000-0000-000000000001'::uuid,
    'Haircut',
    'Precision haircuts, fades, scissor work, and traditional trims tailored to your personal style.'
  ),
  (
    'c0000000-0000-0000-0000-000000000002'::uuid,
    'Beard',
    'Beard shaping, razor line-ups, and relaxing hot towel treatments.'
  ),
  (
    'c0000000-0000-0000-0000-000000000003'::uuid,
    'Styling',
    'Washes, blowouts, pomade styling, and modern hair finishing.'
  ),
  (
    'c0000000-0000-0000-0000-000000000004'::uuid,
    'Treatments & Spa',
    'Scalp detox, deep conditioning, and relaxing head and shoulder massage.'
  ),
  (
    'c0000000-0000-0000-0000-000000000005'::uuid,
    'Packages & Combos',
    'Full grooming packages combining haircuts, beard detailing, and treatments.'
  )
on conflict (name) do update
set description = excluded.description;

-- ============================================================================
-- 2. SERVICES
-- ============================================================================
insert into public.services (
  id,
  name,
  category_id,
  duration_minutes,
  price,
  cost,
  description,
  image_url,
  is_active
)
values
  (
    's0000000-0000-0000-0000-000000000001'::uuid,
    'Classic Haircut',
    (select id from public.service_categories where name = 'Haircut'),
    30,
    25.00,
    5.00,
    'A clean, classic cut finished with a neck taper and razor cleanup.',
    'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000002'::uuid,
    'Skin Fade',
    (select id from public.service_categories where name = 'Haircut'),
    45,
    35.00,
    7.00,
    'Zero fade blended seamlessly into your chosen length on top with crisp outlines.',
    'https://images.unsplash.com/photo-1622286342621-4bd786c2447c?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000003'::uuid,
    'Kids Haircut',
    (select id from public.service_categories where name = 'Haircut'),
    30,
    18.00,
    3.00,
    'Gentle, patient haircut service for children under 12 years old.',
    'https://images.unsplash.com/photo-1595152772835-219674b2a8a6?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000004'::uuid,
    'Scissor Cut & Texture',
    (select id from public.service_categories where name = 'Haircut'),
    45,
    40.00,
    8.00,
    'Full shear/scissor cut for longer hair with custom texture and styling.',
    'https://images.unsplash.com/photo-1517832606589-7629c3395909?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000005'::uuid,
    'Beard Grooming',
    (select id from public.service_categories where name = 'Beard'),
    30,
    18.00,
    4.00,
    'Beard trim, cheek/neck line sculpting, and organic beard oil treatment.',
    'https://images.unsplash.com/photo-1621605815971-fbc98d665033?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000006'::uuid,
    'Hot Towel Shave',
    (select id from public.service_categories where name = 'Beard'),
    35,
    28.00,
    6.00,
    'Traditional straight razor shave with pre-shave oil, hot steam towels, and soothing balm.',
    'https://images.unsplash.com/photo-1512690459411-b9245aed614b?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000007'::uuid,
    'Hair Styling',
    (select id from public.service_categories where name = 'Styling'),
    30,
    20.00,
    4.00,
    'Invigorating shampoo wash, blow dry, and premium matte clay or pomade styling.',
    'https://images.unsplash.com/photo-1585747860715-2ba37e788b70?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000008'::uuid,
    'Haircut and Beard',
    (select id from public.service_categories where name = 'Haircut'),
    60,
    45.00,
    9.00,
    'The full package: tailored haircut plus full beard shaping and hot towel finish.',
    'https://images.unsplash.com/photo-1599351431202-1e0f0137899a?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000009'::uuid,
    'Scalp Treatment & Massage',
    (select id from public.service_categories where name = 'Treatments & Spa'),
    30,
    32.00,
    6.00,
    'Exfoliating tea tree scalp scrub and tension-relieving head massage.',
    'https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000010'::uuid,
    'Deep Conditioning Mask',
    (select id from public.service_categories where name = 'Treatments & Spa'),
    25,
    24.00,
    5.00,
    'Moisturizing hair mask to repair dry hair and nourish scalp roots.',
    'https://images.unsplash.com/photo-1560066984-138dadb4c035?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000011'::uuid,
    'The Royal Treatment',
    (select id from public.service_categories where name = 'Packages & Combos'),
    75,
    70.00,
    15.00,
    'Haircut, straight razor hot towel shave, scalp massage, and facial scrub.',
    'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?w=600',
    true
  ),
  (
    's0000000-0000-0000-0000-000000000012'::uuid,
    'Father & Son Duo',
    (select id from public.service_categories where name = 'Packages & Combos'),
    60,
    52.00,
    10.00,
    'Two haircuts for father and son with complimentary beverage and styling.',
    'https://images.unsplash.com/photo-1516975080664-ed2fc6a32937?w=600',
    true
  )
on conflict (name) do update
set category_id = excluded.category_id,
    duration_minutes = excluded.duration_minutes,
    price = excluded.price,
    cost = excluded.cost,
    description = excluded.description,
    image_url = coalesce(excluded.image_url, services.image_url),
    is_active = excluded.is_active;

-- ============================================================================
-- 3. STAFF / BARBERS
-- ============================================================================
insert into public.staff (
  id,
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
values
  (
    'e0000000-0000-0000-0000-000000000001'::uuid,
    'Marcus Vance',
    '+1 (555) 234-5671',
    'marcus.vance@barbershop.com',
    'Master Barber',
    'Precision Fades, Hot Towel Shave, Beard Design, Scissor Work',
    35.00,
    15.000,
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
    true
  ),
  (
    'e0000000-0000-0000-0000-000000000002'::uuid,
    'David Miller',
    '+1 (555) 234-5672',
    'david.miller@barbershop.com',
    'Senior Fade Specialist',
    'Skin Fades, Taper Fades, Razor Lineups, Textured Crops',
    30.00,
    12.500,
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
    true
  ),
  (
    'e0000000-0000-0000-0000-000000000003'::uuid,
    'Alex Rivera',
    '+1 (555) 234-5673',
    'alex.rivera@barbershop.com',
    'Stylist & Barber',
    'Scissor Cuts, Pompadours, Hair Coloring, Modern Styling',
    32.00,
    14.000,
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
    true
  ),
  (
    'e0000000-0000-0000-0000-000000000004'::uuid,
    'Sarah Chen',
    '+1 (555) 234-5674',
    'sarah.chen@barbershop.com',
    'Grooming & Spa Specialist',
    'Scalp Massage, Deep Conditioning, Classic Haircuts, Facials',
    28.00,
    10.000,
    'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400',
    true
  ),
  (
    'e0000000-0000-0000-0000-000000000005'::uuid,
    'Liam Bennett',
    '+1 (555) 234-5675',
    'liam.bennett@barbershop.com',
    'Junior Barber',
    'Buzz Cuts, Traditional Tapers, Beard Trims, Neck Shaves',
    22.00,
    8.000,
    'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=400',
    true
  )
on conflict (lower(btrim(name))) do update
set phone = excluded.phone,
    email = excluded.email,
    role = excluded.role,
    skills = excluded.skills,
    pay_rate = excluded.pay_rate,
    commission_rate = excluded.commission_rate,
    profile_photo = coalesce(excluded.profile_photo, staff.profile_photo),
    is_active = excluded.is_active;

-- ============================================================================
-- 4. CUSTOMERS
-- ============================================================================
insert into public.customers (
  id,
  full_name,
  phone,
  email,
  registration_date,
  date_of_birth,
  gender,
  notes,
  profile_picture
)
values
  (
    'd0000000-0000-0000-0000-000000000001'::uuid,
    'James Wilson',
    '+1 (555) 456-7801',
    'james.wilson@example.com',
    current_date - 120,
    '1990-05-14',
    'Male',
    'Prefers low skin fade and pomade finish. VIP regular.',
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200'
  ),
  (
    'd0000000-0000-0000-0000-000000000002'::uuid,
    'Robert Martinez',
    '+1 (555) 456-7802',
    'robert.martinez@example.com',
    current_date - 90,
    '1985-08-22',
    'Male',
    'Sensitive skin, use unscented pre-shave oil.',
    'https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?w=200'
  ),
  (
    'd0000000-0000-0000-0000-000000000003'::uuid,
    'Daniel Kim',
    '+1 (555) 456-7803',
    'daniel.kim@example.com',
    current_date - 60,
    '1994-11-03',
    'Male',
    'Regular every 2 weeks. Textured crop with taper.',
    'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=200'
  ),
  (
    'd0000000-0000-0000-0000-000000000004'::uuid,
    'Anthony Davis',
    '+1 (555) 456-7804',
    'anthony.davis@example.com',
    current_date - 45,
    '1988-02-19',
    'Male',
    'Loves hot towel shaves with eucalyptus steam.',
    'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=200'
  ),
  (
    'd0000000-0000-0000-0000-000000000005'::uuid,
    'Chris Taylor',
    '+1 (555) 456-7805',
    'chris.taylor@example.com',
    current_date - 30,
    '1998-07-30',
    'Male',
    'College athlete, high and tight fade.',
    'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=200'
  ),
  (
    'd0000000-0000-0000-0000-000000000006'::uuid,
    'Ethan Wright',
    '+1 (555) 456-7806',
    'ethan.wright@example.com',
    current_date - 20,
    '1992-12-14',
    'Male',
    'Prefers evening appointments after 5 PM.',
    'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=200'
  ),
  (
    'd0000000-0000-0000-0000-000000000007'::uuid,
    'Michael Brown',
    '+1 (555) 456-7807',
    'michael.brown@example.com',
    current_date - 15,
    '1983-03-09',
    'Male',
    'Visits with his son for Father & Son duo combo.',
    'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200'
  ),
  (
    'd0000000-0000-0000-0000-000000000008'::uuid,
    'Oliver Thomas',
    '+1 (555) 456-7808',
    'oliver.thomas@example.com',
    current_date - 5,
    '1996-09-25',
    'Male',
    'New customer, referred by James Wilson.',
    'https://images.unsplash.com/photo-1501196354995-cbb51c65aaea?w=200'
  )
on conflict (phone) do update
set full_name = excluded.full_name,
    email = excluded.email,
    date_of_birth = excluded.date_of_birth,
    gender = excluded.gender,
    notes = excluded.notes,
    profile_picture = coalesce(excluded.profile_picture, customers.profile_picture);

-- ============================================================================
-- 5. APPOINTMENTS
-- Time calculations are anchored to Singapore timezone (Asia/Singapore).
-- All appointments for each barber are spaced out to satisfy appointments_staff_no_overlap.
-- ============================================================================

-- Reference timestamp: start of today at 00:00:00 Singapore time
with time_anchor as (
  select date_trunc('day', now() at time zone 'Asia/Singapore') as today_sg
),
seed_appts (
  id,
  customer_id,
  staff_id,
  service_id,
  start_offset_days,
  start_hour,
  start_minute,
  duration_mins,
  status,
  source,
  notes
) as (
  values
    -- Staff 1: Marcus Vance (Master Barber)
    (
      'a0000000-0000-0000-0000-000000000001'::uuid,
      'd0000000-0000-0000-0000-000000000001'::uuid, -- James Wilson
      'e0000000-0000-0000-0000-000000000001'::uuid, -- Marcus Vance
      's0000000-0000-0000-0000-000000000008'::uuid, -- Haircut and Beard (60m)
      -4, 10, 0, 60,
      'completed'::public.appointment_status, 'web'::public.appointment_source,
      'Wants sharp beard lines and natural neck taper.'
    ),
    (
      'a0000000-0000-0000-0000-000000000002'::uuid,
      'd0000000-0000-0000-0000-000000000003'::uuid, -- Daniel Kim
      'e0000000-0000-0000-0000-000000000001'::uuid, -- Marcus Vance
      's0000000-0000-0000-0000-000000000002'::uuid, -- Skin Fade (45m)
      -2, 14, 0, 45,
      'completed'::public.appointment_status, 'web'::public.appointment_source,
      'Low skin fade, finger length on top.'
    ),
    (
      'a0000000-0000-0000-0000-000000000003'::uuid,
      'd0000000-0000-0000-0000-000000000006'::uuid, -- Ethan Wright
      'e0000000-0000-0000-0000-000000000001'::uuid, -- Marcus Vance
      's0000000-0000-0000-0000-000000000001'::uuid, -- Classic Haircut (30m)
      0, 10, 0, 30,
      'confirmed'::public.appointment_status, 'phone'::public.appointment_source,
      'Regular trim before weekend event.'
    ),
    (
      'a0000000-0000-0000-0000-000000000004'::uuid,
      'd0000000-0000-0000-0000-000000000008'::uuid, -- Oliver Thomas
      'e0000000-0000-0000-0000-000000000001'::uuid, -- Marcus Vance
      's0000000-0000-0000-0000-000000000011'::uuid, -- The Royal Treatment (75m)
      1, 14, 0, 75,
      'confirmed'::public.appointment_status, 'web'::public.appointment_source,
      'First appointment at shop, VIP royal package.'
    ),

    -- Staff 2: David Miller (Senior Fade Specialist)
    (
      'a0000000-0000-0000-0000-000000000005'::uuid,
      'd0000000-0000-0000-0000-000000000002'::uuid, -- Robert Martinez
      'e0000000-0000-0000-0000-000000000002'::uuid, -- David Miller
      's0000000-0000-0000-0000-000000000006'::uuid, -- Hot Towel Shave (35m)
      -3, 11, 30, 35,
      'completed'::public.appointment_status, 'walk-in'::public.appointment_source,
      'Hot steam towel and soothing aloe vera balm.'
    ),
    (
      'a0000000-0000-0000-0000-000000000006'::uuid,
      'd0000000-0000-0000-0000-000000000004'::uuid, -- Anthony Davis
      'e0000000-0000-0000-0000-000000000002'::uuid, -- David Miller
      's0000000-0000-0000-0000-000000000005'::uuid, -- Beard Grooming (30m)
      -1, 15, 0, 30,
      'completed'::public.appointment_status, 'web'::public.appointment_source,
      'Beard trim and organic beard butter.'
    ),
    (
      'a0000000-0000-0000-0000-000000000007'::uuid,
      'd0000000-0000-0000-0000-000000000005'::uuid, -- Chris Taylor
      'e0000000-0000-0000-0000-000000000002'::uuid, -- David Miller
      's0000000-0000-0000-0000-000000000002'::uuid, -- Skin Fade (45m)
      0, 13, 30, 45,
      'in-service'::public.appointment_status, 'web'::public.appointment_source,
      'Mid drop fade with textured top.'
    ),
    (
      'a0000000-0000-0000-0000-000000000008'::uuid,
      'd0000000-0000-0000-0000-000000000001'::uuid, -- James Wilson
      'e0000000-0000-0000-0000-000000000002'::uuid, -- David Miller
      's0000000-0000-0000-0000-000000000006'::uuid, -- Hot Towel Shave (35m)
      2, 11, 0, 35,
      'pending'::public.appointment_status, 'web'::public.appointment_source,
      'Post-gym shave.'
    ),

    -- Staff 3: Alex Rivera (Stylist & Barber)
    (
      'a0000000-0000-0000-0000-000000000009'::uuid,
      'd0000000-0000-0000-0000-000000000007'::uuid, -- Michael Brown
      'e0000000-0000-0000-0000-000000000003'::uuid, -- Alex Rivera
      's0000000-0000-0000-0000-000000000004'::uuid, -- Scissor Cut & Texture (45m)
      -5, 16, 0, 45,
      'completed'::public.appointment_status, 'phone'::public.appointment_source,
      'Layered scissor cut, blow-dry finish.'
    ),
    (
      'a0000000-0000-0000-0000-000000000010'::uuid,
      'd0000000-0000-0000-0000-000000000003'::uuid, -- Daniel Kim
      'e0000000-0000-0000-0000-000000000003'::uuid, -- Alex Rivera
      's0000000-0000-0000-0000-000000000007'::uuid, -- Hair Styling (30m)
      0, 16, 0, 30,
      'confirmed'::public.appointment_status, 'web'::public.appointment_source,
      'Styling for business dinner.'
    ),
    (
      'a0000000-0000-0000-0000-000000000011'::uuid,
      'd0000000-0000-0000-0000-000000000005'::uuid, -- Chris Taylor
      'e0000000-0000-0000-0000-000000000003'::uuid, -- Alex Rivera
      's0000000-0000-0000-0000-000000000001'::uuid, -- Classic Haircut (30m)
      -1, 9, 0, 30,
      'canceled'::public.appointment_status, 'web'::public.appointment_source,
      'Customer canceled due to emergency meeting.'
    ),

    -- Staff 4: Sarah Chen (Grooming & Spa Specialist)
    (
      'a0000000-0000-0000-0000-000000000012'::uuid,
      'd0000000-0000-0000-0000-000000000006'::uuid, -- Ethan Wright
      'e0000000-0000-0000-0000-000000000004'::uuid, -- Sarah Chen
      's0000000-0000-0000-0000-000000000009'::uuid, -- Scalp Treatment (30m)
      -3, 15, 0, 30,
      'completed'::public.appointment_status, 'web'::public.appointment_source,
      'Scalp exfoliation and therapeutic massage.'
    ),
    (
      'a0000000-0000-0000-0000-000000000013'::uuid,
      'd0000000-0000-0000-0000-000000000002'::uuid, -- Robert Martinez
      'e0000000-0000-0000-0000-000000000004'::uuid, -- Sarah Chen
      's0000000-0000-0000-0000-000000000010'::uuid, -- Deep Conditioning Mask (25m)
      0, 17, 15, 25,
      'confirmed'::public.appointment_status, 'web'::public.appointment_source,
      'Hydration mask treatment.'
    ),

    -- Staff 5: Liam Bennett (Junior Barber)
    (
      'a0000000-0000-0000-0000-000000000014'::uuid,
      'd0000000-0000-0000-0000-000000000007'::uuid, -- Michael Brown
      'e0000000-0000-0000-0000-000000000005'::uuid, -- Liam Bennett
      's0000000-0000-0000-0000-000000000003'::uuid, -- Kids Haircut (30m)
      -2, 11, 0, 30,
      'completed'::public.appointment_status, 'walk-in'::public.appointment_source,
      'First haircut for 6-year-old son.'
    ),
    (
      'a0000000-0000-0000-0000-000000000015'::uuid,
      'd0000000-0000-0000-0000-000000000008'::uuid, -- Oliver Thomas
      'e0000000-0000-0000-0000-000000000005'::uuid, -- Liam Bennett
      's0000000-0000-0000-0000-000000000001'::uuid, -- Classic Haircut (30m)
      3, 15, 30, 30,
      'booked'::public.appointment_status, 'web'::public.appointment_source,
      'Standard side part trim.'
    )
)
insert into public.appointments (
  id,
  customer_id,
  staff_id,
  service_id,
  start_time,
  end_time,
  status,
  source,
  notes
)
select
  s.id,
  s.customer_id,
  s.staff_id,
  s.service_id,
  (t.today_sg + (s.start_offset_days || ' days')::interval + (s.start_hour || ' hours')::interval + (s.start_minute || ' minutes')::interval) at time zone 'Asia/Singapore',
  (t.today_sg + (s.start_offset_days || ' days')::interval + (s.start_hour || ' hours')::interval + ((s.start_minute + s.duration_mins) || ' minutes')::interval) at time zone 'Asia/Singapore',
  s.status,
  s.source,
  s.notes
from seed_appts s
cross join time_anchor t
on conflict (id) do update
set customer_id = excluded.customer_id,
    staff_id = excluded.staff_id,
    service_id = excluded.service_id,
    start_time = excluded.start_time,
    end_time = excluded.end_time,
    status = excluded.status,
    source = excluded.source,
    notes = excluded.notes;

-- ============================================================================
-- 6. TRANSACTIONS
-- Populates completed transactions linked to completed appointments,
-- plus today's walk-in and past month historical totals for analytics charts.
-- ============================================================================
insert into public.transactions (
  id,
  appointment_id,
  customer_id,
  staff_id,
  amount,
  tip_amount,
  tax_amount,
  payment_method,
  status,
  created_at
)
values
  -- Completed Appt 1: James Wilson / Marcus Vance
  (
    't0000000-0000-0000-0000-000000000001'::uuid,
    'a0000000-0000-0000-0000-000000000001'::uuid,
    'd0000000-0000-0000-0000-000000000001'::uuid,
    'e0000000-0000-0000-0000-000000000001'::uuid,
    45.00,
    8.00,
    3.60,
    'card'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('day', now() at time zone 'Asia/Singapore') - interval '4 days' + interval '11 hours') at time zone 'Asia/Singapore'
  ),
  -- Completed Appt 2: Daniel Kim / Marcus Vance
  (
    't0000000-0000-0000-0000-000000000002'::uuid,
    'a0000000-0000-0000-0000-000000000002'::uuid,
    'd0000000-0000-0000-0000-000000000003'::uuid,
    'e0000000-0000-0000-0000-000000000001'::uuid,
    35.00,
    5.00,
    2.80,
    'mobile'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('day', now() at time zone 'Asia/Singapore') - interval '2 days' + interval '14 hours 45 minutes') at time zone 'Asia/Singapore'
  ),
  -- Completed Appt 5: Robert Martinez / David Miller
  (
    't0000000-0000-0000-0000-000000000003'::uuid,
    'a0000000-0000-0000-0000-000000000005'::uuid,
    'd0000000-0000-0000-0000-000000000002'::uuid,
    'e0000000-0000-0000-0000-000000000002'::uuid,
    28.00,
    5.00,
    2.24,
    'cash'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('day', now() at time zone 'Asia/Singapore') - interval '3 days' + interval '12 hours 05 minutes') at time zone 'Asia/Singapore'
  ),
  -- Completed Appt 6: Anthony Davis / David Miller
  (
    't0000000-0000-0000-0000-000000000004'::uuid,
    'a0000000-0000-0000-0000-000000000006'::uuid,
    'd0000000-0000-0000-0000-000000000004'::uuid,
    'e0000000-0000-0000-0000-000000000002'::uuid,
    18.00,
    4.00,
    1.44,
    'card'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('day', now() at time zone 'Asia/Singapore') - interval '1 day' + interval '15 hours 30 minutes') at time zone 'Asia/Singapore'
  ),
  -- Completed Appt 9: Michael Brown / Alex Rivera
  (
    't0000000-0000-0000-0000-000000000005'::uuid,
    'a0000000-0000-0000-0000-000000000009'::uuid,
    'd0000000-0000-0000-0000-000000000007'::uuid,
    'e0000000-0000-0000-0000-000000000003'::uuid,
    40.00,
    6.00,
    3.20,
    'card'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('day', now() at time zone 'Asia/Singapore') - interval '5 days' + interval '16 hours 45 minutes') at time zone 'Asia/Singapore'
  ),
  -- Completed Appt 12: Ethan Wright / Sarah Chen
  (
    't0000000-0000-0000-0000-000000000006'::uuid,
    'a0000000-0000-0000-0000-000000000012'::uuid,
    'd0000000-0000-0000-0000-000000000006'::uuid,
    'e0000000-0000-0000-0000-000000000004'::uuid,
    32.00,
    5.00,
    2.56,
    'mobile'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('day', now() at time zone 'Asia/Singapore') - interval '3 days' + interval '15 hours 30 minutes') at time zone 'Asia/Singapore'
  ),
  -- Completed Appt 14: Michael Brown / Liam Bennett
  (
    't0000000-0000-0000-0000-000000000007'::uuid,
    'a0000000-0000-0000-0000-000000000014'::uuid,
    'd0000000-0000-0000-0000-000000000007'::uuid,
    'e0000000-0000-0000-0000-000000000005'::uuid,
    18.00,
    3.00,
    1.44,
    'cash'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('day', now() at time zone 'Asia/Singapore') - interval '2 days' + interval '11 hours 30 minutes') at time zone 'Asia/Singapore'
  ),
  -- Today's walk-in morning transaction (guarantees revenue_today in dashboard)
  (
    't0000000-0000-0000-0000-000000000008'::uuid,
    null,
    'd0000000-0000-0000-0000-000000000008'::uuid, -- Oliver Thomas
    'e0000000-0000-0000-0000-000000000001'::uuid, -- Marcus Vance
    35.00,
    5.00,
    2.80,
    'card'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('day', now() at time zone 'Asia/Singapore') + interval '9 hours') at time zone 'Asia/Singapore'
  ),
  -- Historical transactions for monthly revenue analytics chart
  (
    't0000000-0000-0000-0000-000000000009'::uuid,
    null,
    'd0000000-0000-0000-0000-000000000001'::uuid,
    'e0000000-0000-0000-0000-000000000001'::uuid,
    380.00,
    45.00,
    30.40,
    'card'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('month', now() at time zone 'Asia/Singapore') - interval '3 months' + interval '10 days') at time zone 'Asia/Singapore'
  ),
  (
    't0000000-0000-0000-0000-000000000010'::uuid,
    null,
    'd0000000-0000-0000-0000-000000000003'::uuid,
    'e0000000-0000-0000-0000-000000000002'::uuid,
    540.00,
    60.00,
    43.20,
    'mobile'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('month', now() at time zone 'Asia/Singapore') - interval '2 months' + interval '12 days') at time zone 'Asia/Singapore'
  ),
  (
    't0000000-0000-0000-0000-000000000011'::uuid,
    null,
    'd0000000-0000-0000-0000-000000000005'::uuid,
    'e0000000-0000-0000-0000-000000000003'::uuid,
    720.00,
    85.00,
    57.60,
    'card'::public.payment_method_type,
    'completed'::public.transaction_status,
    (date_trunc('month', now() at time zone 'Asia/Singapore') - interval '1 month' + interval '14 days') at time zone 'Asia/Singapore'
  )
on conflict (id) do update
set appointment_id = excluded.appointment_id,
    customer_id = excluded.customer_id,
    staff_id = excluded.staff_id,
    amount = excluded.amount,
    tip_amount = excluded.tip_amount,
    tax_amount = excluded.tax_amount,
    payment_method = excluded.payment_method,
    status = excluded.status,
    created_at = excluded.created_at;

-- ============================================================================
-- 7. CUSTOMER FEEDBACK & REVIEWS
-- Links completed appointments with satisfied 5-star customer reviews.
-- ============================================================================
insert into public.feedback (
  id,
  appointment_id,
  customer_id,
  rating,
  comments
)
values
  (
    'f0000000-0000-0000-0000-000000000001'::uuid,
    'a0000000-0000-0000-0000-000000000001'::uuid,
    'd0000000-0000-0000-0000-000000000001'::uuid,
    5,
    'Marcus is hands down the best barber in town. Flawless fade and the beard oil smelled amazing.'
  ),
  (
    'f0000000-0000-0000-0000-000000000002'::uuid,
    'a0000000-0000-0000-0000-000000000002'::uuid,
    'd0000000-0000-0000-0000-000000000003'::uuid,
    5,
    'Cleanest skin fade I have had in years. Great attention to detail and zero wait time.'
  ),
  (
    'f0000000-0000-0000-0000-000000000003'::uuid,
    'a0000000-0000-0000-0000-000000000005'::uuid,
    'd0000000-0000-0000-0000-000000000002'::uuid,
    5,
    'The hot towel shave was ultra relaxing. Very gentle on sensitive skin. Highly recommend David!'
  ),
  (
    'f0000000-0000-0000-0000-000000000004'::uuid,
    'a0000000-0000-0000-0000-000000000009'::uuid,
    'd0000000-0000-0000-0000-000000000007'::uuid,
    5,
    'Alex did wonders with scissor work. My hair holds shape perfectly without needing heavy wax.'
  ),
  (
    'f0000000-0000-0000-0000-000000000005'::uuid,
    'a0000000-0000-0000-0000-000000000012'::uuid,
    'd0000000-0000-0000-0000-000000000006'::uuid,
    5,
    'Sarah is fantastic. The scalp massage relieved a week worth of stress. Definitely booking regularly.'
  ),
  (
    'f0000000-0000-0000-0000-000000000006'::uuid,
    'a0000000-0000-0000-0000-000000000014'::uuid,
    'd0000000-0000-0000-0000-000000000007'::uuid,
    5,
    'Liam was so patient with my 6yo son. Best kid haircut experience we have ever had.'
  )
on conflict (appointment_id, customer_id) do update
set rating = excluded.rating,
    comments = excluded.comments;

commit;
