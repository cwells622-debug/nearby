-- ChadAds: rename 'Autos Cars' -> 'Auto Cars', 'Autos Trucks' -> 'Auto Trucks', and add 'Auto SUVs'.
-- Run in the Supabase SQL Editor, then push the matching site change right away (the site looks the categories up by name).
-- Safe to run more than once. Deletes nothing: renaming keeps every ad in its category.
-- Moving existing ads into Auto SUVs is done from the admin page (Edit -> Category), or with the optional lines at the bottom.

-- 1. The rule about which categories may have a link now knows all three Auto categories (old names kept for the moment).
create or replace function public.check_listing_link()
returns trigger
language plpgsql
as $$
begin
  if new.link is not null
     and not exists (select 1 from public.categories
                     where id = new.category_id
                       and name in ('Auto Cars', 'Auto Trucks', 'Auto SUVs', 'Autos Cars', 'Autos Trucks', 'Vehicles')) then
    raise exception 'Only Auto Cars, Auto Trucks and Auto SUVs ads can have a link.';
  end if;
  return new;
end;
$$;

-- 2. Rename.
update public.categories set name = 'Auto Cars'   where name = 'Autos Cars';
update public.categories set name = 'Auto Trucks' where name = 'Autos Trucks';

-- 3. New category.
insert into public.categories (name, icon) values ('Auto SUVs', '🚙')
on conflict (name) do nothing;

-- Optional: the Jeep Rubicon (ad 38) and Ford Bronco (ad 48) are SUVs. Remove the two dashes at the start of the next 3 lines to move them.
-- update public.listings
-- set category_id = (select id from public.categories where name = 'Auto SUVs')
-- where id in (38, 48);

-- Check (optional)
-- select c.name, count(l.id) from public.categories c left join public.listings l on l.category_id = c.id where c.name like 'Auto%' group by c.name order by c.name;
