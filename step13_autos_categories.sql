-- Nearby: split "Vehicles" into "Autos Cars" and "Autos Trucks"
-- Run this in the Supabase SQL Editor. Safe to run more than once (and safe to re-run after a failed attempt). It deletes nothing.
--
-- 1. The rule about which categories may have a link is updated FIRST (otherwise the database would
--    refuse to move an ad that has a link, because it only knew the old name "Vehicles").
-- 2. The old "Vehicles" category is RENAMED to "Autos Cars", so every ad already in it keeps its category.
-- 3. A new category "Autos Trucks" is added.
-- 4. Two existing ads are moved to it: ad 23 (the Ford F250) and ad 38 (the 2017 Jeep Rubicon, a 4x4).
--    Change this list if you disagree; ad 36 (Mitsubishi Lancer) stays in Cars. You can also move any ad
--    later from the admin page (admin.html -> Edit -> Category).

-- 1. The rule that decides which categories may have a link: both Autos categories (and the old name, for the moment).
create or replace function public.check_listing_link()
returns trigger
language plpgsql
as $$
begin
  if new.link is not null
     and not exists (select 1 from public.categories
                     where id = new.category_id
                       and name in ('Autos Cars', 'Autos Trucks', 'Vehicles')) then
    raise exception 'Only Autos Cars and Autos Trucks ads can have a link.';
  end if;
  return new;
end;
$$;

-- 2. Rename.
update public.categories set name = 'Autos Cars', icon = '🚗' where name = 'Vehicles';

-- 3. New category.
insert into public.categories (name, icon) values ('Autos Trucks', '🛻')
on conflict (name) do nothing;

-- 4. Move the two ads.
update public.listings
set category_id = (select id from public.categories where name = 'Autos Trucks')
where id in (23, 38)
  and exists (select 1 from public.categories where name = 'Autos Trucks');

-- Check (optional): this should show Autos Cars with the Lancer, and Autos Trucks with the F250 and the Jeep.
-- select l.id, l.title, c.name from public.listings l join public.categories c on c.id = l.category_id order by c.name, l.id;
