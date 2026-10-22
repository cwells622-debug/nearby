-- ChadAds: small copies (thumbnails) for the photos that the dealer importer copies in.
-- Run in the Supabase SQL Editor AFTER step23_dealer_feed.sql. Safe to run more than once. Deletes nothing.
--
-- Photos uploaded by members get a small copy (name_t.jpg, about 600 px wide) made in their own browser. Photos copied in by the dealer importer
-- have none, so every grid card loaded the full-size photo (100 to 250 KB each). The GitHub job (.github/scripts/fetch_feed.py) now makes the
-- small copies with an image library and sends each one to the importer, which stores it next to the photo. This table column remembers which
-- photos already have one, and two helper functions (only the importer can call them) hand out the work and note what is done.

alter table public.listing_photos add column if not exists has_thumb boolean not null default false;

-- The next photos of active dealer ads that still need a small copy (oldest first).
create or replace function public.feed_thumb_candidates(p_limit int default 100)
returns table (id bigint, storage_path text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.storage_path
  from public.listing_photos p
  join public.listings l on l.id = p.listing_id
  join public.profiles pr on pr.id = l.seller_id
  where not p.has_thumb and l.status = 'active' and pr.is_dealer
  order by p.id
  limit greatest(least(p_limit, 500), 0)
$$;

-- The path of one photo, so the importer can store its small copy next to it.
create or replace function public.feed_thumb_target(p_id bigint)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.storage_path from public.listing_photos p
  join public.listings l on l.id = p.listing_id
  join public.profiles pr on pr.id = l.seller_id
  where p.id = p_id and pr.is_dealer
$$;

create or replace function public.feed_thumb_done(p_id bigint)
returns void
language sql
security definer
set search_path = public
as $$
  update public.listing_photos set has_thumb = true where id = p_id
$$;

revoke execute on function public.feed_thumb_candidates(int), public.feed_thumb_target(bigint), public.feed_thumb_done(bigint) from public, anon, authenticated;
grant  execute on function public.feed_thumb_candidates(int), public.feed_thumb_target(bigint), public.feed_thumb_done(bigint) to service_role;

-- How many still need one:  select count(*) from public.listing_photos p join public.listings l on l.id = p.listing_id join public.profiles pr on pr.id = l.seller_id where not p.has_thumb and l.status = 'active' and pr.is_dealer;
