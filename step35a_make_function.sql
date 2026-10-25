-- ChadAds: "Make" for Auto Cars / Trucks / SUVs (Ford, Chevrolet, Toyota ...), plus two categories: Fun Finds and Furniture.
-- Run in the Supabase SQL Editor AFTER step32_featured.sql. Safe to run more than once. Deletes nothing.
--
-- HOW IT WORKS
--   * listings.make holds the make. It fills itself: when an ad in Auto Cars, Auto Trucks or Auto SUVs is saved with no make, the database reads it
--     from the title (the dealer feed titles look like "2026 Ford F-150 Lariat ...", so dealer cars need no importer change). A make typed or picked
--     by a seller is tidied up ("chevy" -> "Chevrolet", "vw" -> "Volkswagen").
--   * The page shows a row of make buttons (with counts) inside those three categories; clicking one filters the ads (p_make in browse_ads).
--   * Fun Finds is a new category. Furniture already existed but was switched off; this switches it back on.

-- PART A of 3 (run these three files in order: step35a, step35b, step35c).

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
    ('acura','Acura'),('alfa[- ]?romeo','Alfa Romeo'),('amc|american motors','AMC'),
    ('aston martin','Aston Martin'),('audi','Audi'),('austin[- ]healey','Austin-Healey'),
    ('bentley','Bentley'),('bmw','BMW'),('buick','Buick'),
    ('cadillac|caddy','Cadillac'),('chevrolet|chevy','Chevrolet'),('chrysler','Chrysler'),
    ('datsun','Datsun'),('desoto','DeSoto'),('dodge','Dodge'),
    ('edsel','Edsel'),('ferrari','Ferrari'),('fiat','Fiat'),
    ('ford','Ford'),('genesis','Genesis'),('gmc','GMC'),
    ('graham','Graham'),('honda','Honda'),('hudson','Hudson'),
    ('hummer','Hummer'),('hyundai','Hyundai'),('infiniti','Infiniti'),
    ('international|scout','International'),('isuzu','Isuzu'),('jaguar','Jaguar'),
    ('jeep|willys','Jeep'),('kia','Kia'),('lamborghini','Lamborghini'),
    ('land[- ]?rover|range rover','Land Rover'),('lexus','Lexus'),('lincoln','Lincoln'),
    ('lotus','Lotus'),('maserati','Maserati'),('mazda','Mazda'),
    ('mercedes([- ]?benz)?|benz','Mercedes-Benz'),('mercury','Mercury'),('mg','MG'),
    ('mini cooper|mini','Mini'),('mitsubishi','Mitsubishi'),('nash','Nash'),
    ('nissan','Nissan'),('oldsmobile|olds','Oldsmobile'),('packard','Packard'),
    ('plymouth','Plymouth'),('polestar','Polestar'),('pontiac','Pontiac'),
    ('porsche','Porsche'),('ram','Ram'),('rivian','Rivian'),
    ('rolls[- ]?royce','Rolls-Royce'),('saab','Saab'),('saturn','Saturn'),
    ('scion','Scion'),('studebaker','Studebaker'),('subaru','Subaru'),
    ('suzuki','Suzuki'),('tesla','Tesla'),('toyota','Toyota'),
    ('triumph','Triumph'),('volkswagen|vw','Volkswagen'),('volvo','Volvo')
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

