-- ChadAds: city search (so every US town can be picked when posting an ad)
-- Run in the Supabase SQL Editor AFTER step15_regions.sql and AFTER the five step17_cities_1..5.sql files. Safe to run more than once. Deletes nothing.
--
-- WHAT IT DOES
--  1. search_cities(): finds cities as you type in the Post form (Saratoga ... Saratoga Springs, NY). New York and place names
--     inside a region come first, so a New Yorker typing "Chester" sees the right one near the top.
--  2. nearest_city(): finds the closest place to a spot on the map (for the "Use my location" button).
--  3. Sets the regions (Capital District, Adirondacks, ...) for the new places, the same way step15_regions.sql does.
--     NOTE: the county of each new place was worked out from the nearest town centre, which is right about 97% of the time.
--     A place right on a county line can land in the wrong county; fix one with:  update public.cities set county_fips = '113' where name = '...' and state = 'NY';
--     then run section 3 below again.

-- 1. Search as you type. "north creek" or "north creek, ny" both work.
create or replace function public.search_cities(q text, lim int default 15)
returns table (id bigint, name text, state text, lat double precision, lng double precision, regions text[])
language sql stable as $$
  with parts as (
    select case when position(',' in q) > 0 then trim(split_part(q, ',', 1)) else trim(q) end as nm,
           case when position(',' in q) > 0 then upper(trim(split_part(q, ',', 2))) else '' end as st
  )
  select c.id, c.name, c.state, c.lat, c.lng, c.regions
  from public.cities c, parts
  where length(parts.nm) >= 2
    and c.name ilike replace(replace(replace(parts.nm, '\', '\\'), '%', '\%'), '_', '\_') || '%'
    and (parts.st = '' or c.state like parts.st || '%')
  order by (lower(c.name) = lower(parts.nm)) desc,
           (c.regions <> '{}') desc,
           (c.state = 'NY') desc,
           c.name, c.state
  limit least(greatest(lim, 1), 30)
$$;

-- 2. The closest place to a point on the map.
create or replace function public.nearest_city(p_lat double precision, p_lng double precision)
returns table (id bigint, name text, state text, lat double precision, lng double precision, regions text[])
language sql stable as $$
  select c.id, c.name, c.state, c.lat, c.lng, c.regions
  from public.cities c
  order by (c.lat - p_lat) ^ 2 + ((c.lng - p_lng) * cos(radians(p_lat))) ^ 2
  limit 1
$$;

grant execute on function public.search_cities(text, int) to anon, authenticated;
grant execute on function public.nearest_city(double precision, double precision) to anon, authenticated;

-- 3. Regions (same rules as step15_regions.sql, section 3: if you change a region there, change it here too).
--    County codes (FIPS) for New York: Albany 001, Clinton 019, Columbia 021, Dutchess 027, Essex 031, Franklin 033,
--    Greene 039, Hamilton 041, Orange 071, Rensselaer 083, Saratoga 091, Schenectady 093, Sullivan 105, Ulster 111,
--    Warren 113, Washington 115. Excluded from every region: NYC (005,047,061,081,085), Long Island (059,103),
--    Westchester 119, Rockland 087 and Putnam 079.
update public.cities set regions = '{}';

update public.cities set regions = array_append(regions, 'capital-district')
where (state = 'NY' and county_fips in ('001','083','091','093'))
   or (state = 'VT' and county_fips = '003')   -- Bennington County, Vermont
   or (state = 'MA' and county_fips = '003'); -- Berkshire County, Massachusetts

update public.cities set regions = array_append(regions, 'adirondacks')
where state = 'NY' and (county_fips in ('113','031','041','019')
   or (county_fips = '033' and name in ('Saranac Lake','Tupper Lake'))
   or (county_fips = '115' and name = 'Hudson Falls'));

update public.cities set regions = array_append(regions, 'hudson-valley')
where state = 'NY' and county_fips in ('021','039','027','111','071','105');

update public.cities set regions = array_append(regions, 'upstate-new-york')
where state = 'NY' and county_fips is not null
  and county_fips not in ('005','047','061','081','085','059','103','119','087','079');

-- Check (optional): how many places are in each region?
-- select r as region, count(*) from public.cities, unnest(regions) r group by r order by r;
-- Try the search:  select * from public.search_cities('north creek');
