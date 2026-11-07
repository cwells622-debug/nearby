-- ChadAds: two more categories (Local Businesses, Want Ad)
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- The website picks them up by itself (menus, Post form, category pages).

insert into public.categories (name, icon) values
  ('Local Businesses', '🏪'),
  ('Want Ad',          '🔎')
on conflict (name) do nothing;
