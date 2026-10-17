-- ChadAds: three more categories (Boats, Snowmobiles, Auto Parts)
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- The website picks them up by itself (menus, Post form, category pages); the page change that comes with this
-- only adds their short descriptions for search engines and the Sell page links.

insert into public.categories (name, icon) values
  ('Boats',       '🚤'),
  ('Snowmobiles', '🛷'),
  ('Auto Parts',  '⚙️')
on conflict (name) do nothing;
