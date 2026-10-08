-- Nearby: cover photo choice and cover framing (Marketplace-style grid tiles)
-- Run this in the Supabase SQL Editor AFTER step4 and step8. Safe to run more than once.
-- It only adds two columns and two rules; it never deletes any data.

-- 1. Photo order. The photo with the LOWEST number is the cover (shown on the grid).
--    Everything is 0 today; "make cover" gives the chosen photo -1.
alter table public.listing_photos add column if not exists position integer not null default 0;

-- 2. How the cover is framed in the grid tile, as a percentage from the top
--    (0 = show the top of the photo, 50 = centre, 100 = show the bottom).
alter table public.listings add column if not exists cover_y smallint not null default 50;
alter table public.listings drop constraint if exists listings_cover_y_range;
alter table public.listings add constraint listings_cover_y_range check (cover_y between 0 and 100);

-- 3. Owners may re-order their OWN photos (this is the only thing that changes in that table).
drop policy if exists "users update photos of own listings" on public.listing_photos;
create policy "users update photos of own listings"
  on public.listing_photos for update
  using (exists (select 1 from public.listings l where l.id = listing_id and l.seller_id = auth.uid()))
  with check (
    storage_path like auth.uid()::text || '/%'
    and exists (select 1 from public.listings l where l.id = listing_id and l.seller_id = auth.uid()));

drop policy if exists "admins update any photo row" on public.listing_photos;
create policy "admins update any photo row"
  on public.listing_photos for update
  using (public.is_admin())
  with check (public.is_admin());
