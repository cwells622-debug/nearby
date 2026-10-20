-- ChadAds: dealer inventory feed (the database side).
-- Run in the Supabase SQL Editor AFTER step8_admin.sql, step4_photos_and_limits.sql and step20_email_alerts.sql (for the private schema).
-- Safe to run more than once. Deletes nothing.
--
-- HOW THE WHOLE THING FITS TOGETHER
--   * ONE feed file (from carsforsale.com) can contain the cars of MANY dealers. Each row has a DealerID.
--   * Each dealer you want on ChadAds has a normal ChadAds account, marked as a "dealer", and a line saying
--     "DealerID 247256 = Marchese Ford, New Lebanon NY, this account". Cars from DealerIDs you have not added are IGNORED
--     (and listed in the preview so you can see who is missing).
--   * A small program (the Supabase Edge Function "import-feed", file supabase/functions/import-feed/index.ts) reads the feed link,
--     splits the cars by DealerID and adds / updates / hides each dealer's ads. Cars are matched by VIN, so nothing is duplicated.
--   * The feed link is a secret: it is stored in the private tables below and nowhere else, never in GitHub and never on the website.
--
-- ADDING A NEW DEALER LATER: they sign up on chadads.com, then you run ONE line (see section 6). That is all.

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

-- 3. The feeds and their dealers. Private: the website can never read these.
create schema if not exists private;
create table if not exists private.feed_sources (
  id          bigint generated always as identity primary key,
  name        text not null unique,              -- e.g. 'carsforsale.com'
  feed_url    text,                              -- the secret link to the inventory file
  active      boolean not null default false,    -- switch the whole feed on/off without deleting it
  last_run_at timestamptz,
  last_result text
);
create table if not exists private.feed_dealers (
  id          bigint generated always as identity primary key,
  source_id   bigint not null references private.feed_sources (id) on delete cascade,
  dealer_code text not null,                     -- the DealerID column in the feed
  seller_id   uuid   not null references public.profiles (id),
  dealer_name text   not null,
  city_id     bigint not null references public.cities (id),
  active      boolean not null default true,     -- switch one dealer off without touching the others
  unique (source_id, dealer_code)
);
alter table private.feed_sources enable row level security;   -- no policies = only the database owner and the importer
alter table private.feed_dealers enable row level security;
revoke all on private.feed_sources, private.feed_dealers from anon, authenticated;
-- (An earlier draft of this file made a table private.dealer_feeds. It is no longer used; it is left alone, nothing is deleted.)

-- 4. The importer (running as the project's service role) calls these. Nobody else can.
create or replace function public.feed_check_secret(s text)
returns boolean
language sql
security definer
set search_path = public, private
as $$
  select exists (select 1 from private.app_secrets where name = 'import_secret' and value = s and s <> '')
$$;

-- All active feeds, each with its active dealers, as one piece of JSON.
create or replace function public.feed_get_config()
returns jsonb
language sql
security definer
set search_path = public, private
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'name', s.name, 'feed_url', s.feed_url,
    'dealers', (select coalesce(jsonb_agg(jsonb_build_object(
                  'code', d.dealer_code, 'seller_id', d.seller_id, 'name', d.dealer_name,
                  'city_id', d.city_id, 'city_name', c.name, 'state', c.state)), '[]'::jsonb)
                from private.feed_dealers d join public.cities c on c.id = d.city_id
                where d.source_id = s.id and d.active))), '[]'::jsonb)
  from private.feed_sources s
  where s.active and s.feed_url is not null and s.feed_url <> ''
$$;

create or replace function public.feed_save_result(p_id bigint, p_result text)
returns void
language sql
security definer
set search_path = public, private
as $$
  update private.feed_sources set last_run_at = now(), last_result = left(p_result, 3000) where id = p_id
$$;

revoke execute on function public.feed_check_secret(text), public.feed_get_config(), public.feed_save_result(bigint, text) from public, anon, authenticated;
grant  execute on function public.feed_check_secret(text), public.feed_get_config(), public.feed_save_result(bigint, text) to service_role;

-- 5. THE ONE-LINE WAY TO ADD A DEALER (you run it in the SQL Editor; nobody else can).
--    It marks the dealer's ChadAds account as a dealer, sets the name shown on the site, and links DealerID -> account -> town.
--    Run it again with new details to change a dealer.
create or replace function private.add_feed_dealer(p_source text, p_code text, p_email text, p_name text, p_city text, p_state text)
returns text
language plpgsql
as $$
declare sid bigint; uid uuid; cid bigint;
begin
  select id into sid from private.feed_sources where name = p_source;
  if sid is null then raise exception 'There is no feed called "%". Add it first (section 6, step A).', p_source; end if;
  select id into uid from auth.users where lower(email) = lower(p_email);
  if uid is null then raise exception 'There is no ChadAds account with the email "%". The dealer must sign up on chadads.com first.', p_email; end if;
  select id into cid from public.cities where name = p_city and state = p_state;
  if cid is null then raise exception 'The town "%, %" is not in the city list.', p_city, p_state; end if;
  update public.profiles set is_dealer = true, display_name = left(p_name, 40) where id = uid;
  insert into private.feed_dealers (source_id, dealer_code, seller_id, dealer_name, city_id)
  values (sid, p_code, uid, p_name, cid)
  on conflict (source_id, dealer_code) do update
    set seller_id = excluded.seller_id, dealer_name = excluded.dealer_name, city_id = excluded.city_id, active = true;
  return 'OK: DealerID ' || p_code || ' = ' || p_name || ', ' || p_city || ', ' || p_state || ' (account ' || p_email || ')';
end;
$$;
revoke all on function private.add_feed_dealer(text, text, text, text, text, text) from public, anon, authenticated;

-- 6. SETUP (run each of these once in the SQL Editor; replace the capital-letter placeholders; keep the quote marks).
--
--    A. Add the feed. Leave the link as a placeholder until you have the real one; it stays OFF (false) so nothing runs:
--       insert into private.feed_sources (name, feed_url, active) values ('carsforsale.com', 'PASTE-THE-FEED-LINK-HERE', false)
--       on conflict (name) do nothing;
--
--    B. Add each dealer (they must already have signed up on chadads.com; the number is the DealerID from the feed):
--       select private.add_feed_dealer('carsforsale.com', '247256', 'DEALER-EMAIL-HERE', 'Marchese Ford', 'New Lebanon', 'NY');
--
--    C. A secret word the schedule uses to prove it is allowed to run the importer (make up long random text; never save it in GitHub):
--       insert into private.app_secrets (name, value) values ('import_secret', 'PASTE-A-LONG-RANDOM-TEXT-HERE')
--       on conflict (name) do update set value = excluded.value;
--
--    LATER, when you have the real link:
--       update private.feed_sources set feed_url = 'THE-REAL-FEED-LINK' where name = 'carsforsale.com';
--    Turn the feed on / off:
--       update private.feed_sources set active = true  where name = 'carsforsale.com';
--       update private.feed_sources set active = false where name = 'carsforsale.com';
--    Pause one dealer:   update private.feed_dealers set active = false where dealer_code = '247256';
--    See the last result: select name, active, last_run_at, last_result from private.feed_sources;
--    See your dealers:    select dealer_code, dealer_name, active from private.feed_dealers order by dealer_name;
