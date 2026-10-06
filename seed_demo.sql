-- Nearby: demo listings (Phase 1, step 3)
-- Run this in the Supabase SQL Editor AFTER schema.sql.
-- These are the prototype's 20 sample ads, marked is_demo = true so they
-- are easy to find and remove later.
-- Safe to run twice: it adds nothing if demo listings already exist.
--
-- To delete all demo ads later (only when you decide to):
--   delete from public.listings where is_demo;

insert into public.listings (category_id, city_id, title, description, price, created_at, is_demo)
select cat.id, ci.id, d.title, d.descr, d.price, now() - d.age, true
from (values
  ('2016 Honda Civic, 82k miles',    'Vehicles',    'Saratoga Springs', 'NY', 'One owner, clean title, new tires. Service records available.', 11800, interval '2 hours'),
  ('Trek mountain bike, size M',     'Sports',      'Ballston Spa',     'NY', 'Lightly used, recently tuned. Includes helmet.', 350, interval '3 hours'),
  ('Sunny 2-bedroom apartment',      'Property',    'Albany',           'NY', 'Per month. Near bus line, laundry in building, pets allowed.', 1650, interval '5 hours'),
  ('iPhone 13, 128GB, unlocked',     'Electronics', 'Clifton Park',     'NY', 'Battery health 91%. Comes with case and charger.', 420, interval '1 day'),
  ('Leather sofa, three-seater',     'Furniture',   'Schenectady',      'NY', 'Good condition, pickup only. Buyer must bring help.', 240, interval '1 day'),
  ('Winter jacket, women''s M',      'Clothing',    'Troy',             'NY', 'Worn one season. Warm, waterproof, no stains.', 45, interval '2 days'),
  ('Line cook, full time',           'Jobs',        'Saratoga Springs', 'NY', 'Busy restaurant, $22/hr plus tips. Message to apply.', 0, interval '2 days'),
  ('Gaming laptop, RTX 3060',        'Electronics', 'Albany',           'NY', '16GB RAM, 1TB SSD. Runs current games well.', 780, interval '3 days'),
  ('Oak dining table with 4 chairs', 'Furniture',   'Glens Falls',      'NY', 'Solid wood, a few light scratches.', 180, interval '3 days'),
  ('Studio room for rent',           'Property',    'Troy',             'NY', 'Per month, utilities included. Quiet street.', 900, interval '4 days'),
  ('2012 Subaru Outback',            'Vehicles',    'Queensbury',       'NY', 'AWD, 140k miles, runs great. Snow tires included.', 6200, interval '4 days'),
  ('Dog walker needed, weekdays',    'Jobs',        'Saratoga Springs', 'NY', 'Two mid-day walks, $20 each. References please.', 0, interval '5 days'),
  ('Yoga mat and blocks set',        'Sports',      'Clifton Park',     'NY', 'Barely used. Mat, two blocks, strap.', 20, interval '5 days'),
  ('Denim jacket, men''s L',         'Clothing',    'Albany',           'NY', 'Classic fit, great condition.', 30, interval '6 days'),
  ('Standing desk, electric',        'Furniture',   'Boston',           'MA', 'Adjustable height, 60 inch top. Barely used.', 210, interval '6 hours'),
  ('Carbon road bike, size 54',      'Sports',      'Burlington',       'VT', 'Light, well kept, new chain and tires.', 900, interval '8 hours'),
  ('Studio apartment near downtown', 'Property',    'Hartford',         'CT', 'Per month, heat included. Walk to shops.', 1400, interval '1 day'),
  ('2018 Toyota Camry, 61k miles',   'Vehicles',    'New York',         'NY', 'Clean history, single owner.', 14500, interval '2 days'),
  ('Nintendo Switch with 3 games',   'Electronics', 'Pittsburgh',       'PA', 'Includes dock, two controllers, and games.', 190, interval '3 days'),
  ('Barista, part time',             'Jobs',        'Syracuse',         'NY', 'Weekend shifts, $17/hr plus tips. Training provided.', 0, interval '4 days')
) as d(title, cat, city, st, descr, price, age)
join public.categories cat on cat.name = d.cat
join public.cities ci on ci.name = d.city and ci.state = d.st
where not exists (select 1 from public.listings where is_demo);
