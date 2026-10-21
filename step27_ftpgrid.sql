-- ChadAds: read the dealer feed from an ftpGrid drop box (carsforsale.com pushes its file to ftpGrid by FTP; the importer reads it).
-- Run in the Supabase SQL Editor AFTER step23_dealer_feed.sql and step25_feed_upload.sql. Safe to run more than once. Deletes nothing.
--
-- WHAT IT ADDS: private columns on the feed (server, folder, three login keys, and a note of the last file processed), and the two helper
-- functions are updated to hand them to the importer. The keys are secrets: they live only in the private table, never on the website or in GitHub.
-- A feed uses the drop box when ftp_server is filled in (it wins over feed_url).

alter table private.feed_sources
  add column if not exists ftp_server          text,                         -- e.g. web3.ftpgrid.com  (ftpGrid dashboard > Settings)
  add column if not exists ftp_folder          text not null default '/',    -- the folder carsforsale.com puts the file in
  add column if not exists ftp_association_key text,
  add column if not exists ftp_access_key      text,
  add column if not exists ftp_secret_key      text,
  add column if not exists ftp_last_stamp      text;                         -- "file name|modified|size" of the last file fully imported (so it is not re-read every hour)

-- A feed is ready to run on its own when it has a link OR a drop box.
create or replace function public.feed_get_config()
returns jsonb
language sql
security definer
set search_path = public, private
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'name', s.name, 'feed_url', s.feed_url,
    'ftp', case when coalesce(s.ftp_server, '') <> '' then jsonb_build_object(
             'server', s.ftp_server, 'folder', s.ftp_folder, 'association_key', s.ftp_association_key,
             'access_key', s.ftp_access_key, 'secret_key', s.ftp_secret_key, 'last_stamp', s.ftp_last_stamp) end,
    'dealers', (select coalesce(jsonb_agg(jsonb_build_object(
                  'code', d.dealer_code, 'seller_id', d.seller_id, 'name', d.dealer_name,
                  'city_id', d.city_id, 'city_name', c.name, 'state', c.state)), '[]'::jsonb)
                from private.feed_dealers d join public.cities c on c.id = d.city_id
                where d.source_id = s.id and d.active))), '[]'::jsonb)
  from private.feed_sources s
  where s.active and (coalesce(s.feed_url, '') <> '' or coalesce(s.ftp_server, '') <> '')
$$;

create or replace function public.feed_get_source(p_name text)
returns jsonb
language sql
security definer
set search_path = public, private
as $$
  select jsonb_build_object(
    'id', s.id, 'name', s.name, 'feed_url', s.feed_url,
    'ftp', case when coalesce(s.ftp_server, '') <> '' then jsonb_build_object(
             'server', s.ftp_server, 'folder', s.ftp_folder, 'association_key', s.ftp_association_key,
             'access_key', s.ftp_access_key, 'secret_key', s.ftp_secret_key, 'last_stamp', s.ftp_last_stamp) end,
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
  update private.feed_sources set ftp_last_stamp = left(p_stamp, 500) where id = p_id
$$;

revoke execute on function public.feed_get_config(), public.feed_get_source(text), public.feed_save_stamp(bigint, text) from public, anon, authenticated;
grant  execute on function public.feed_get_config(), public.feed_get_source(text), public.feed_save_stamp(bigint, text) to service_role;

-- SETUP (run once in the SQL Editor; replace the capital-letter parts; keep the quote marks; never paste the keys into chat or GitHub):
--   ftpGrid dashboard: Settings shows your server (like web3.ftpgrid.com) and the Association Key; Dashboard > REST API creates the Access Key and Secret Key
--   (give that REST API account the scopes file.list and file.read only).
--
--   update private.feed_sources set
--     ftp_server = 'WEBN.ftpgrid.com', ftp_folder = '/',
--     ftp_association_key = 'ASSOCIATION-KEY', ftp_access_key = 'ACCESS-KEY', ftp_secret_key = 'SECRET-KEY',
--     feed_url = null, active = true
--   where name = 'carsforsale.com';
--
--   Forget the file it last imported (to force a re-read):  update private.feed_sources set ftp_last_stamp = null where name = 'carsforsale.com';
--   See the last result:  select name, active, ftp_server, ftp_folder, ftp_last_stamp, last_run_at, last_result from private.feed_sources;
