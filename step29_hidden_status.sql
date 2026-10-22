-- ChadAds: a new ad status "hidden" (used for dealer cars that have no pictures yet).
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
--
-- Until now an ad was either 'active' (shown) or 'sold' (not shown). The dealer importer now keeps a car out of sight until the feed has pictures for it:
-- such cars get the status 'hidden'. They are not shown to visitors (the site only shows 'active' ads), they are not in the sitemap, and they
-- appear automatically as soon as pictures arrive. Admins can see them (admin page, status filter) and change the status by hand.

alter table public.listings drop constraint if exists listings_status_check;
alter table public.listings add constraint listings_status_check check (status in ('active', 'sold', 'hidden'));
