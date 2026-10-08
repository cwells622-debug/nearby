-- Nearby: three more categories (Farm Equipment, Trailers, Tools)
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- The website picks them up by itself; no page change is needed.

insert into public.categories (name, icon) values
  ('Farm Equipment', '🌾'),
  ('Trailers',       '🚛'),
  ('Tools',          '🔧')
on conflict (name) do nothing;
