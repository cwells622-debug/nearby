-- Nearby: optional "link" field for Vehicles ads
-- Run this in the Supabase SQL Editor. Safe to run more than once.
-- It only adds a column; it never deletes any data.

-- 1. The new column. Empty (null) for every existing ad.
alter table public.listings add column if not exists link text;

-- 2. The link must start with http:// or https:// (this blocks things like
--    "javascript:..." that could be used to attack visitors), have no
--    spaces, and be at most 500 characters.
alter table public.listings drop constraint if exists listings_link_format;
alter table public.listings add constraint listings_link_format
  check (link is null or (link ~* '^https?://[^[:space:]]+$' and char_length(link) <= 500));

-- 3. Only Vehicles ads may have a link. A trigger is code the database runs
--    automatically before saving a row; raising an error refuses the save.
create or replace function public.check_listing_link()
returns trigger
language plpgsql
as $$
begin
  if new.link is not null
     and not exists (select 1 from public.categories
                     where id = new.category_id and name = 'Vehicles') then
    raise exception 'Only Vehicles ads can have a link.';
  end if;
  return new;
end;
$$;

drop trigger if exists listings_link_check on public.listings;
create trigger listings_link_check
  before insert or update on public.listings
  for each row execute function public.check_listing_link();
