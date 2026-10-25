-- ChadAds step35 PART C of 3: the two categories, and filling in the make of the car ads that exist already. Run AFTER step35b_browse_make.sql.

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
