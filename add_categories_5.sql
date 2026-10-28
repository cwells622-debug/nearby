-- ChadAds: two more categories (Home Appliances, E-Bikes)
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- The website picks them up by itself (menus, Post form, category pages). The old, switched-off "Appliances" category is left alone.

insert into public.categories (name, icon) values
  ('Home Appliances', '🧺'),
  ('E-Bikes',         '⚡')
on conflict (name) do nothing;
