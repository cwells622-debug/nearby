-- Nearby: nine more categories
-- Run this in the Supabase SQL Editor. Safe to run more than once
-- (a category that already exists is skipped). It never deletes anything.
-- The website picks up new categories by itself; no page change is needed.

insert into public.categories (name, icon) values
  ('ATV',             '🏁'),
  ('Appliances',      '🧺'),
  ('Campers',         '🏕️'),
  ('Real Estate',     '🏡'),
  ('Medical',         '🩺'),
  ('Motorcycles',     '🏍️'),
  ('Antiques',        '🏺'),
  ('Lawn and Garden', '🌱'),
  ('Heavy Machinery', '🚜')
on conflict (name) do nothing;
