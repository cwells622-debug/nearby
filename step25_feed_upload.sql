-- ChadAds: "Upload a feed file" (admin page, Dealer feeds tab). The database side: one helper the importer calls.
-- Run in the Supabase SQL Editor AFTER step23_dealer_feed.sql. Safe to run more than once. Deletes nothing.
--
-- When you upload a file, the importer needs the feed's dealer list (which DealerID is which account and town) even if the feed has
-- no link and is switched off. This returns the named feed with its active dealers. Only the importer (service role) can call it.

create or replace function public.feed_get_source(p_name text)
returns jsonb
language sql
security definer
set search_path = public, private
as $$
  select jsonb_build_object(
    'id', s.id, 'name', s.name, 'feed_url', s.feed_url,
    'dealers', (select coalesce(jsonb_agg(jsonb_build_object(
                  'code', d.dealer_code, 'seller_id', d.seller_id, 'name', d.dealer_name,
                  'city_id', d.city_id, 'city_name', c.name, 'state', c.state)), '[]'::jsonb)
                from private.feed_dealers d join public.cities c on c.id = d.city_id
                where d.source_id = s.id and d.active))
  from private.feed_sources s
  where s.name = p_name
$$;

revoke execute on function public.feed_get_source(text) from public, anon, authenticated;
grant  execute on function public.feed_get_source(text) to service_role;
