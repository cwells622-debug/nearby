-- ChadAds: "Make" for Auto Cars / Trucks / SUVs (Ford, Chevrolet, Toyota ...), plus two categories: Fun Finds and Furniture.
-- Run in the Supabase SQL Editor AFTER step32_featured.sql. Safe to run more than once. Deletes nothing.
--
-- HOW IT WORKS
--   * listings.make holds the make. It fills itself: when an ad in Auto Cars, Auto Trucks or Auto SUVs is saved with no make, the database reads it
--     from the title (the dealer feed titles look like "2026 Ford F-150 Lariat ...", so dealer cars need no importer change). A make typed or picked
--     by a seller is tidied up ("chevy" -> "Chevrolet", "vw" -> "Volkswagen").
--   * The page shows a row of make buttons (with counts) inside those three categories; clicking one filters the ads (p_make in browse_ads).
--   * Fun Finds is a new category. Furniture already existed but was switched off; this switches it back on.
-- To teach it another make or spelling, add it to the list in guess_make() below and run this file again (the backfill at the bottom fills the old ads).

alter table public.listings add column if not exists make text;
create index if not exists listings_make_idx on public.listings (category_id, make) where make is not null;

-- 1. Reads a make out of some text: the one that appears FIRST in it ("Dodge Ram 1500" -> Dodge). Returns null when none is found.
create or replace function public.guess_make(t text)
returns text
language sql
immutable
as $$
  select m.display
  from (values
    ('acura','Acura'),('alfa[- ]?romeo','Alfa Romeo'),('amc|american motors','AMC'),('aston martin','Aston Martin'),('audi','Audi'),('austin[- ]healey','Austin-Healey'),('bentley','Bentley'),
    ('bmw','BMW'),('buick','Buick'),('cadillac|caddy','Cadillac'),('chevrolet|chevy','Chevrolet'),('chrysler','Chrysler'),('datsun','Datsun'),('desoto','DeSoto'),
    ('dodge','Dodge'),('edsel','Edsel'),('ferrari','Ferrari'),('fiat','Fiat'),('ford','Ford'),('genesis','Genesis'),('gmc','GMC'),('graham','Graham'),('honda','Honda'),
    ('hudson','Hudson'),('hummer','Hummer'),('hyundai','Hyundai'),('infiniti','Infiniti'),('international|scout','International'),('isuzu','Isuzu'),('jaguar','Jaguar'),
    ('jeep|willys','Jeep'),('kia','Kia'),('lamborghini','Lamborghini'),('land[- ]?rover|range rover','Land Rover'),('lexus','Lexus'),('lincoln','Lincoln'),('lotus','Lotus'),
    ('maserati','Maserati'),('mazda','Mazda'),('mercedes([- ]?benz)?|benz','Mercedes-Benz'),('mercury','Mercury'),('mg','MG'),('mini cooper|mini','Mini'),('mitsubishi','Mitsubishi'),
    ('nash','Nash'),('nissan','Nissan'),('oldsmobile|olds','Oldsmobile'),('packard','Packard'),('plymouth','Plymouth'),('polestar','Polestar'),('pontiac','Pontiac'),
    ('porsche','Porsche'),('ram','Ram'),('rivian','Rivian'),('rolls[- ]?royce','Rolls-Royce'),('saab','Saab'),('saturn','Saturn'),('scion','Scion'),('studebaker','Studebaker'),
    ('subaru','Subaru'),('suzuki','Suzuki'),('tesla','Tesla'),('toyota','Toyota'),('triumph','Triumph'),('volkswagen|vw','Volkswagen'),('volvo','Volvo')
  ) as m(pattern, display)
  where t ~* ('\m(' || m.pattern || ')\M')
  order by length(regexp_replace(t, '\m(' || m.pattern || ')\M.*$', '', 'i')),   -- how far into the text the make starts
           length(m.display) desc
  limit 1
$$;

-- 2. Before an ad is saved in a car category: fill in or tidy up its make.
create or replace function public.listings_fill_make()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from public.categories c where c.id = new.category_id and c.name in ('Auto Cars', 'Auto Trucks', 'Auto SUVs')) then
    if coalesce(btrim(new.make), '') = '' then
      new.make := public.guess_make(new.title);
    else
      new.make := coalesce(public.guess_make(new.make), left(btrim(new.make), 30));
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists listings_fill_make on public.listings;
create trigger listings_fill_make before insert or update on public.listings
  for each row execute function public.listings_fill_make();

-- 3. The ad finder (from step32) with one more choice: p_make. The old version is replaced (its list of choices changed).
drop function if exists public.browse_ads(text, bigint, text, double precision, double precision, double precision, text, text, bigint[], int, int, int);

create or replace function public.browse_ads(
  p_q       text             default null,
  p_cat     bigint           default null,
  p_region  text             default null,
  p_lat     double precision default null,
  p_lng     double precision default null,
  p_radius  double precision default 0,
  p_sort    text             default 'best',
  p_dealer  text             default 'all',      -- 'all', 'private' or 'dealer'
  p_ids     bigint[]         default null,       -- only these ads (the Saved view)
  p_per_cat int              default null,       -- keep only the first N of each category (the "By category" view)
  p_limit   int              default 48,
  p_offset  int              default 0,
  p_make    text             default null)       -- only this make (Ford, Chevrolet ...) in the car categories
returns table (id bigint, dist double precision, total bigint)
language sql
stable
as $$
  with base as (
    select l.id, l.seller_id, l.category_id, l.created_at, l.price, l.price_on_request, l.featured,
           case when p_lat is null or p_lng is null then null::double precision
                else 3959 * 2 * asin(sqrt(least(1.0,
                       power(sin(radians(c.lat - p_lat) / 2), 2)
                       + cos(radians(p_lat)) * cos(radians(c.lat)) * power(sin(radians(c.lng - p_lng) / 2), 2)))) end as dist
    from public.listings l
    join public.cities c on c.id = l.city_id
    join public.categories cat on cat.id = l.category_id
    left join public.profiles pr on pr.id = l.seller_id
    where l.status = 'active'
      and cat.active
      and (p_cat is null or l.category_id = p_cat)
      and (p_region is null or p_region = any (c.regions))
      and (p_ids is null or l.id = any (p_ids))
      and (p_make is null or l.make = p_make)
      and (coalesce(p_dealer, 'all') = 'all'
           or (p_dealer = 'dealer' and coalesce(pr.is_dealer, false))
           or (p_dealer = 'private' and not coalesce(pr.is_dealer, false)))
      and (coalesce(btrim(p_q), '') = ''
           or l.title ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
           or l.description ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
           or c.name ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%')
  ),
  near as (
    select * from base
    where coalesce(p_radius, 0) <= 0 or p_lat is null or dist <= p_radius
  ),
  turns as (
    select *,
           row_number() over (partition by seller_id order by created_at desc, id desc) as turn,
           case when dist is null then 0 when dist <= 100 then 0 when dist <= 250 then 1 else 2 end as bucket
    from near
  ),
  ordered as (
    select *,
           row_number() over (order by
             case when p_sort in ('best', 'new', 'near') and featured then 0 else 1 end,   -- featured ads first (premium placement)
             case when p_sort = 'best' then bucket end,
             case when p_sort = 'best' then turn end,
             case when p_sort = 'low'  then (case when price_on_request then 1e12 else price end) end,
             case when p_sort = 'high' then (case when price_on_request then -1 else price end) end desc,
             case when p_sort = 'near' then dist end,
             case when p_sort = 'old'  then created_at end,
             created_at desc, id desc) as pos
    from turns
  ),
  per_cat as (
    select *, row_number() over (partition by category_id order by pos) as cat_pos from ordered
  ),
  picked as (
    select id, dist, pos, count(*) over () as total
    from per_cat
    where p_per_cat is null or cat_pos <= p_per_cat
  )
  select id, dist, total from picked order by pos limit greatest(p_limit, 0) offset greatest(p_offset, 0)
$$;

grant execute on function public.browse_ads(text, bigint, text, double precision, double precision, double precision, text, text, bigint[], int, int, int, text) to anon, authenticated;

-- 4. The make buttons: the makes in one category (with counts), for the same filters as the ad list (but not the make itself).
create or replace function public.browse_makes(
  p_cat     bigint,
  p_q       text             default null,
  p_region  text             default null,
  p_lat     double precision default null,
  p_lng     double precision default null,
  p_radius  double precision default 0,
  p_dealer  text             default 'all')
returns table (make text, n bigint)
language sql
stable
as $$
  select l.make, count(*)::bigint
  from public.listings l
  join public.cities c on c.id = l.city_id
  join public.categories cat on cat.id = l.category_id
  left join public.profiles pr on pr.id = l.seller_id
  where l.status = 'active'
    and cat.active
    and l.category_id = p_cat
    and l.make is not null
    and (p_region is null or p_region = any (c.regions))
    and (coalesce(p_dealer, 'all') = 'all'
         or (p_dealer = 'dealer' and coalesce(pr.is_dealer, false))
         or (p_dealer = 'private' and not coalesce(pr.is_dealer, false)))
    and (coalesce(p_radius, 0) <= 0 or p_lat is null or p_lng is null
         or 3959 * 2 * asin(sqrt(least(1.0,
              power(sin(radians(c.lat - p_lat) / 2), 2)
              + cos(radians(p_lat)) * cos(radians(c.lat)) * power(sin(radians(c.lng - p_lng) / 2), 2)))) <= p_radius)
    and (coalesce(btrim(p_q), '') = ''
         or l.title ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
         or l.description ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
         or c.name ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%')
  group by l.make
  order by count(*) desc, l.make
$$;
grant execute on function public.browse_makes(bigint, text, text, double precision, double precision, double precision, text) to anon, authenticated;

-- 5. Two categories.
insert into public.categories (name, icon) values ('Fun Finds', '🎁') on conflict (name) do nothing;
update public.categories set active = true where name = 'Furniture';

-- 6. Fill in the make of the car ads that exist already (the trigger does the work when each one is touched).
update public.listings l set make = public.guess_make(l.title)
where coalesce(btrim(l.make), '') = ''
  and l.category_id in (select id from public.categories where name in ('Auto Cars', 'Auto Trucks', 'Auto SUVs'));

-- Check: each make and how many ads it has, then the active car ads that no make was found for (fix those by hand in the admin page).
select make, count(*) as ads from public.listings where make is not null group by make order by 2 desc;
select id, title from public.listings
where make is null and status = 'active' and category_id in (select id from public.categories where name in ('Auto Cars', 'Auto Trucks', 'Auto SUVs'));
