-- ChadAds: dealer inventory feed (the database side).
-- Run in the Supabase SQL Editor AFTER step8_admin.sql, step4_photos_and_limits.sql and step20_email_alerts.sql (for the private schema).
-- Safe to run more than once. Deletes nothing.
--
-- HOW THE WHOLE THING FITS TOGETHER
--   * A dealer (Marchese Ford) has a normal ChadAds account that you mark as a "dealer" (section 5 below).
--   * A small program (the Supabase Edge Function "import-feed", file supabase/functions/import-feed/index.ts) reads the dealer's
--     feed link, and adds / updates / removes that dealer's ads. Cars are matched by VIN, so nothing is duplicated.
--   * Everything the program needs is read from the private table below, through functions only the program can call.
--     The feed link is a secret: it is stored here and nowhere else, never in GitHub and never shown on the website.

-- 1. Marks a profile as a dealer, and remembers which ad came from which feed row.
alter table public.profiles add column if not exists is_dealer boolean not null default false;
alter table public.listings add column if not exists external_id text;   -- the VIN from the feed
alter table public.listings add column if not exists feed_hash  text;    -- fingerprint of what we last imported (to skip unchanged cars)
create unique index if not exists listings_external_uq on public.listings (seller_id, external_id) where external_id is not null;

-- 2. Dealers may post more than 10 ads a day (the importer adds the whole lot at once).
create or replace function public.limit_listings_per_day()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from public.profiles where id = new.seller_id and is_dealer) then
    return new;
  end if;
  if (select count(*) from public.listings
      where seller_id = new.seller_id
        and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'You can post up to 10 ads per day. Please try again tomorrow.';
  end if;
  return new;
end;
$$;

-- 3. One row per dealer feed. Private: the website can never read it.
create schema if not exists private;
create table if not exists private.dealer_feeds (
  id          bigint generated always as identity primary key,
  seller_id   uuid not null references public.profiles (id),
  dealer_name text not null,
  city_id     bigint not null references public.cities (id),
  feed_url    text,                              -- the secret link to the dealer's inventory file
  active      boolean not null default false,    -- switch a feed on/off without deleting it
  last_run_at timestamptz,
  last_result text
);
alter table private.dealer_feeds enable row level security;   -- no policies = only the database owner and the importer
revoke all on private.dealer_feeds from anon, authenticated;

-- 4. The importer (running as the project's service role) calls these. Nobody else can.
create or replace function public.feed_check_secret(s text)
returns boolean
language sql
security definer
set search_path = public, private
as $$
  select exists (select 1 from private.app_secrets where name = 'import_secret' and value = s and s <> '')
$$;

create or replace function public.feed_get_config()
returns table (id bigint, seller_id uuid, dealer_name text, feed_url text, city_id bigint, city_name text, state text)
language sql
security definer
set search_path = public, private
as $$
  select f.id, f.seller_id, f.dealer_name, f.feed_url, f.city_id, c.name, c.state
  from private.dealer_feeds f join public.cities c on c.id = f.city_id
  where f.active and f.feed_url is not null and f.feed_url <> ''
$$;

create or replace function public.feed_save_result(p_id bigint, p_result text)
returns void
language sql
security definer
set search_path = public, private
as $$
  update private.dealer_feeds set last_run_at = now(), last_result = left(p_result, 2000) where id = p_id
$$;

revoke execute on function public.feed_check_secret(text), public.feed_get_config(), public.feed_save_result(bigint, text) from public, anon, authenticated;
grant  execute on function public.feed_check_secret(text), public.feed_get_config(), public.feed_save_result(bigint, text) to service_role;

-- 5. SET UP MARCHESE FORD (do this once, after they have a ChadAds account; replace the email with the one they signed up with).
--    The account's name on the site becomes "Marchese Ford", and messages and email alerts go to that email address.
--
--    update public.profiles set is_dealer = true, display_name = 'Marchese Ford'
--    where id = (select id from auth.users where email = 'PASTE-THEIR-EMAIL-HERE');
--
--    insert into private.dealer_feeds (seller_id, dealer_name, city_id, feed_url, active)
--    select p.id, 'Marchese Ford', (select id from public.cities where name = 'New Lebanon' and state = 'NY'),
--           'PASTE-THE-FEED-LINK-HERE', false      -- leave false until the preview looks right, then set to true
--    from public.profiles p where p.is_dealer and p.display_name = 'Marchese Ford';
--
--    A secret word the daily schedule uses to prove it is allowed to run the importer (make up a long random text; do not save it in GitHub):
--    insert into private.app_secrets (name, value) values ('import_secret', 'PASTE-A-LONG-RANDOM-TEXT-HERE')
--    on conflict (name) do update set value = excluded.value;
--
--    Turn the feed on:   update private.dealer_feeds set active = true where dealer_name = 'Marchese Ford';
--    See the last result: select dealer_name, active, last_run_at, last_result from private.dealer_feeds;
