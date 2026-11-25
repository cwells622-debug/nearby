-- ChadAds: four more categories (Estate Sales, Bicycles, Musical Instruments, Firewood and Building Materials)
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- The website picks them up by itself (menus, Post form, category pages, sitemap).

insert into public.categories (name, icon) values
  ('Estate Sales',                   '🏷️'),
  ('Bicycles',                       '🚲'),
  ('Musical Instruments',            '🎸'),
  ('Firewood and Building Materials','🪵')
on conflict (name) do nothing;
