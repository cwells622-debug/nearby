-- ChadAds: lets the GitHub job ask "is this file new?" and remember which file it last delivered.
-- Run in the Supabase SQL Editor AFTER step25_feed_upload.sql. Safe to run more than once. Deletes nothing.
--
-- The GitHub job (.github/workflows/fetch-feed.yml) logs into your ftpGrid drop box, finds the newest file, and asks the importer
-- whether it is the same file as last time (a "stamp" = file name | time | size). Only a new file is downloaded and imported. This keeps
-- the free ftpGrid plan (1 GB of downloads a month) from being used up. The stamp is saved here, privately.

alter table private.feed_sources add column if not exists last_stamp text;

-- The upload helper now also returns the last stamp.
create or replace function public.feed_get_source(p_name text)
returns jsonb
language sql
security definer
set search_path = public, private
as $$
  select jsonb_build_object(
    'id', s.id, 'name', s.name, 'feed_url', s.feed_url, 'last_stamp', s.last_stamp,
    'dealers', (select coalesce(jsonb_agg(jsonb_build_object(
                  'code', d.dealer_code, 'seller_id', d.seller_id, 'name', d.dealer_name,
                  'city_id', d.city_id, 'city_name', c.name, 'state', c.state)), '[]'::jsonb)
                from private.feed_dealers d join public.cities c on c.id = d.city_id
                where d.source_id = s.id and d.active))
  from private.feed_sources s
  where s.name = p_name
$$;

create or replace function public.feed_save_stamp(p_id bigint, p_stamp text)
returns void
language sql
security definer
set search_path = public, private
as $$
  update private.feed_sources set last_stamp = left(p_stamp, 500) where id = p_id
$$;

revoke execute on function public.feed_get_source(text), public.feed_save_stamp(bigint, text) from public, anon, authenticated;
grant  execute on function public.feed_get_source(text), public.feed_save_stamp(bigint, text) to service_role;

-- To make the job re-import the same file (for example after fixing a dealer):
--   update private.feed_sources set last_stamp = null where name = 'carsforsale.com';
-- To see what it last delivered:
--   select name, last_stamp, last_run_at, last_result from private.feed_sources;
