-- Nearby: split "Vehicles" into "Autos Cars" and "Autos Trucks"
-- Run this in the Supabase SQL Editor. Safe to run more than once. It deletes nothing.
--
-- 1. The old "Vehicles" category is RENAMED to "Autos Cars", so every ad already in it keeps its category.
-- 2. A new category "Autos Trucks" is added.
-- 3. Two existing ads are moved to it: ad 23 (the Ford F250) and ad 38 (the 2017 Jeep Rubicon, a 4x4).
--    Change this list if you disagree; ad 36 (Mitsubishi Lancer) stays in Cars. You can also move any ad
--    later from the admin page (admin.html -> Edit -> Category).
-- 4. The optional "Link" box on an ad (used for dealer or history-report links) now works for BOTH
--    Autos categories. (Before, it was Vehicles only.)

update public.categories set name = 'Autos Cars', icon = '🚗' where name = 'Vehicles';

insert into public.categories (name, icon) values ('Autos Trucks', '🛻')
on conflict (name) do nothing;

update public.listings
set category_id = (select id from public.categories where name = 'Autos Trucks')
where id in (23, 38)
  and exists (select 1 from public.categories where name = 'Autos Trucks');

-- The rule that decides which categories may have a link.
create or replace function public.check_listing_link()
returns trigger
language plpgsql
as $$
begin
  if new.link is not null
     and not exists (select 1 from public.categories
                     where id = new.category_id and name in ('Autos Cars', 'Autos Trucks')) then
    raise exception 'Only Autos Cars and Autos Trucks ads can have a link.';
  end if;
  return new;
end;
$$;
