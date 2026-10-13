-- ChadAds: "Contact for price" option on an ad.
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- When price_on_request is true the ad shows "Contact for price" instead of a dollar amount (the price column is ignored, kept at 0).
alter table public.listings add column if not exists price_on_request boolean not null default false;
