-- ChadAds: add the city East Chatham, NY (Columbia County).
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- Coordinates from Wikipedia (42.4106 N, 73.5244 W). County 021 = Columbia County, so it gets the same
-- regions as Chatham and the other Columbia County towns (Hudson Valley and Upstate NY).

insert into public.cities (name, state, lat, lng, county_fips, regions) values
  ('East Chatham', 'NY', 42.4106, -73.5244, '021', array['hudson-valley', 'upstate-new-york'])
on conflict (name, state) do nothing;

-- Check (optional): select * from public.cities where name = 'East Chatham';
