-- ChadAds: Local Businesses ads may have a website link, like the car categories.
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- (The old rule only allowed a link on Auto Cars, Auto Trucks and Auto SUVs.)

create or replace function public.check_listing_link()
returns trigger
language plpgsql
as $$
begin
  if new.link is not null
     and not exists (select 1 from public.categories
                     where id = new.category_id
                       and name in ('Auto Cars', 'Auto Trucks', 'Auto SUVs', 'Autos Cars', 'Autos Trucks', 'Vehicles', 'Local Businesses')) then
    raise exception 'Only Auto Cars, Auto Trucks, Auto SUVs and Local Businesses ads can have a link.';
  end if;
  return new;
end;
$$;
