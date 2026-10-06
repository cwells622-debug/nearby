-- Nearby: photo storage and posting limits (Phase 1, step 4)
-- Run this in the Supabase SQL Editor AFTER schema.sql.
-- Safe to run more than once. It never deletes any of your data.

-- =====================================================================
-- 1. PHOTO STORAGE BUCKET
-- =====================================================================
-- A "bucket" is like a folder on the server for uploaded files.
-- Public = anyone can VIEW a photo if they know its address (so the web
-- page can show it). Uploading and deleting are restricted below.
-- The bucket itself refuses anything that isn't a JPG, PNG or WebP image,
-- or that is bigger than 5 MB (5242880 bytes), even if someone bypasses
-- the web page.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Every file is saved as   <your user id>/<random name>.jpg
-- so the first part of the path says who owns the file. These rules let
-- you add, change, or remove files only inside YOUR OWN folder.
-- (storage.foldername(name))[1] is the first folder in the path.

drop policy if exists "users upload photos to own folder" on storage.objects;
create policy "users upload photos to own folder"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'listing-photos'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users update photos in own folder" on storage.objects;
create policy "users update photos in own folder"
  on storage.objects for update to authenticated
  using (bucket_id = 'listing-photos'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users delete photos in own folder" on storage.objects;
create policy "users delete photos in own folder"
  on storage.objects for delete to authenticated
  using (bucket_id = 'listing-photos'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- =====================================================================
-- 2. TIGHTEN THE listing_photos RULE
-- =====================================================================
-- Besides owning the ad, the photo's path must be inside your own folder,
-- so nobody can attach someone else's file to their ad.

drop policy if exists "users add photos to own listings" on public.listing_photos;
create policy "users add photos to own listings"
  on public.listing_photos for insert
  with check (
    storage_path like auth.uid()::text || '/%'
    and exists (select 1 from public.listings l
                where l.id = listing_id and l.seller_id = auth.uid()));

-- =====================================================================
-- 3. POSTING LIMITS
-- =====================================================================
-- A "trigger" is code the database runs automatically before a row is
-- saved. If it raises an error, the row is NOT saved and the web page
-- shows the message.

-- At most 10 new ads per account in any 24 hours.
-- (To change the limit, edit the 10 below and run this file again.)
create or replace function public.limit_listings_per_day()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.listings
      where seller_id = new.seller_id
        and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'You can post up to 10 ads per day. Please try again tomorrow.';
  end if;
  return new;
end;
$$;

drop trigger if exists listings_daily_limit on public.listings;
create trigger listings_daily_limit
  before insert on public.listings
  for each row execute function public.limit_listings_per_day();

-- At most 5 photos per ad. (The page uses one today; this keeps room
-- for more later while stopping abuse.)
create or replace function public.limit_photos_per_listing()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.listing_photos
      where listing_id = new.listing_id) >= 5 then
    raise exception 'An ad can have up to 5 photos.';
  end if;
  return new;
end;
$$;

drop trigger if exists listing_photos_limit on public.listing_photos;
create trigger listing_photos_limit
  before insert on public.listing_photos
  for each row execute function public.limit_photos_per_listing();
