-- Nearby: database schema (Phase 1, step 1)
-- Run this whole file in the Supabase SQL Editor.
-- It is safe to run more than once: tables use "if not exists",
-- policies are dropped and recreated, and seed rows skip duplicates.
-- It never deletes any of your data.

-- =====================================================================
-- 1. TABLES
-- =====================================================================

-- One row per person who signed up. "id" is the same id Supabase Auth
-- gives the login user (like a UserID shared between a Users table and
-- the session in classic ASP).
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'New member'
               check (char_length(display_name) between 1 and 40),
  created_at   timestamptz not null default now()
);

create table if not exists public.categories (
  id   bigint generated always as identity primary key,
  name text not null unique,
  icon text not null
);

create table if not exists public.cities (
  id    bigint generated always as identity primary key,
  name  text not null,
  state text not null,
  lat   double precision not null,
  lng   double precision not null,
  unique (name, state)
);

create table if not exists public.listings (
  id          bigint generated always as identity primary key,
  -- seller_id is empty only for demo ads, which have no real seller.
  seller_id   uuid references public.profiles (id) on delete cascade,
  category_id bigint not null references public.categories (id),
  city_id     bigint not null references public.cities (id),
  title       text not null check (char_length(title) between 1 and 60),
  description text not null check (char_length(description) between 1 and 2000),
  price       integer not null default 0 check (price >= 0),  -- 0 means free
  created_at  timestamptz not null default now(),
  status      text not null default 'active' check (status in ('active', 'sold')),
  is_demo     boolean not null default false,
  check (is_demo or seller_id is not null)
);

create index if not exists listings_category_idx on public.listings (category_id);
create index if not exists listings_city_idx     on public.listings (city_id);
create index if not exists listings_seller_idx   on public.listings (seller_id);
create index if not exists listings_created_idx  on public.listings (created_at desc);

create table if not exists public.listing_photos (
  id           bigint generated always as identity primary key,
  listing_id   bigint not null references public.listings (id) on delete cascade,
  storage_path text not null
);

create index if not exists listing_photos_listing_idx on public.listing_photos (listing_id);

-- One row = "this user saved this listing". The pair is the key, so you
-- can't save the same ad twice.
create table if not exists public.favorites (
  user_id    uuid   not null references public.profiles (id) on delete cascade,
  listing_id bigint not null references public.listings (id) on delete cascade,
  primary key (user_id, listing_id)
);

-- =====================================================================
-- 2. AUTO-CREATE A PROFILE WHEN SOMEONE SIGNS UP
-- =====================================================================
-- Like running an INSERT in your sign-up page, but the database does it
-- itself the moment a new login user appears.
-- "security definer" lets this one function write to profiles even though
-- the brand-new user has no permissions yet.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(left(new.raw_user_meta_data ->> 'display_name', 40), ''),
             nullif(split_part(new.email, '@', 1), ''),
             'New member')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
-- 3. ROW-LEVEL SECURITY
-- =====================================================================
-- RLS = the database checks every read and write against these rules,
-- no matter what the web page asks for. Once RLS is on, anything with no
-- matching policy is DENIED. So we only list what IS allowed.
-- "auth.uid()" is the id of the signed-in user (null if not signed in),
-- a bit like Session("UserID") in classic ASP.

alter table public.profiles       enable row level security;
alter table public.categories     enable row level security;
alter table public.cities         enable row level security;
alter table public.listings       enable row level security;
alter table public.listing_photos enable row level security;
alter table public.favorites      enable row level security;

-- ---- profiles ----
-- Anyone can see a display name (needed for seller cards).
drop policy if exists "profiles are public to read" on public.profiles;
create policy "profiles are public to read"
  on public.profiles for select
  using (true);

-- You can change only your own profile. No insert policy: profiles are
-- created only by the sign-up trigger above. No delete policy either.
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ---- categories and cities ----
-- Everyone can read these lists. Nobody can change them from the website
-- (no insert/update/delete policies). You edit them in the Supabase
-- dashboard, which bypasses these rules.
drop policy if exists "categories are public to read" on public.categories;
create policy "categories are public to read"
  on public.categories for select
  using (true);

drop policy if exists "cities are public to read" on public.cities;
create policy "cities are public to read"
  on public.cities for select
  using (true);

-- ---- listings ----
-- Anyone (even signed out) can read active ads. A signed-in seller can
-- also see their own ads that are sold.
drop policy if exists "read active listings or your own" on public.listings;
create policy "read active listings or your own"
  on public.listings for select
  using (status = 'active' or auth.uid() = seller_id);

-- You can post an ad only as yourself, and you can't mark it as demo.
drop policy if exists "users create own listings" on public.listings;
create policy "users create own listings"
  on public.listings for insert
  with check (auth.uid() = seller_id and is_demo = false);

-- You can edit only your own ads, and can't hand them to someone else
-- or turn one into a demo ad.
drop policy if exists "users update own listings" on public.listings;
create policy "users update own listings"
  on public.listings for update
  using (auth.uid() = seller_id)
  with check (auth.uid() = seller_id and is_demo = false);

drop policy if exists "users delete own listings" on public.listings;
create policy "users delete own listings"
  on public.listings for delete
  using (auth.uid() = seller_id);

-- ---- listing_photos ----
-- A photo can be seen if you can see its ad. (The subquery runs through
-- the listings rules above, so photos of hidden ads stay hidden.)
drop policy if exists "photos visible with their listing" on public.listing_photos;
create policy "photos visible with their listing"
  on public.listing_photos for select
  using (exists (select 1 from public.listings l where l.id = listing_id));

-- You can add or remove photos only on ads you own.
drop policy if exists "users add photos to own listings" on public.listing_photos;
create policy "users add photos to own listings"
  on public.listing_photos for insert
  with check (exists (
    select 1 from public.listings l
    where l.id = listing_id and l.seller_id = auth.uid()));

drop policy if exists "users delete photos from own listings" on public.listing_photos;
create policy "users delete photos from own listings"
  on public.listing_photos for delete
  using (exists (
    select 1 from public.listings l
    where l.id = listing_id and l.seller_id = auth.uid()));

-- ---- favorites ----
-- Fully private: you can see, add, and remove only your own rows.
-- Nobody else can even see what you saved.
drop policy if exists "users read own favorites" on public.favorites;
create policy "users read own favorites"
  on public.favorites for select
  using (auth.uid() = user_id);

drop policy if exists "users add own favorites" on public.favorites;
create policy "users add own favorites"
  on public.favorites for insert
  with check (auth.uid() = user_id);

drop policy if exists "users remove own favorites" on public.favorites;
create policy "users remove own favorites"
  on public.favorites for delete
  using (auth.uid() = user_id);

-- =====================================================================
-- 4. SEED DATA (from the prototype)
-- =====================================================================

insert into public.categories (name, icon) values
  ('Vehicles',    '🚗'),
  ('Property',    '🏠'),
  ('Electronics', '📱'),
  ('Furniture',   '🛋️'),
  ('Clothing',    '👕'),
  ('Sports',      '🚲'),
  ('Jobs',        '💼')
on conflict (name) do nothing;

insert into public.cities (name, state, lat, lng) values
  ('Saratoga Springs', 'NY', 43.083,   -73.785),
  ('Ballston Spa',     'NY', 43.0006,  -73.8487),
  ('Clifton Park',     'NY', 42.8656,  -73.771),
  ('Schenectady',      'NY', 42.8142,  -73.9396),
  ('Albany',           'NY', 42.6526,  -73.7562),
  ('Troy',             'NY', 42.7284,  -73.6918),
  ('Glens Falls',      'NY', 43.3095,  -73.644),
  ('Queensbury',       'NY', 43.3281,  -73.6551),
  ('New York',         'NY', 40.7128,  -74.006),
  ('Buffalo',          'NY', 42.8864,  -78.8784),
  ('Rochester',        'NY', 43.1566,  -77.6088),
  ('Syracuse',         'NY', 43.0481,  -76.1474),
  ('Boston',           'MA', 42.3601,  -71.0589),
  ('Springfield',      'MA', 42.1015,  -72.5898),
  ('Worcester',        'MA', 42.2626,  -71.8023),
  ('Burlington',       'VT', 44.4759,  -73.2121),
  ('Rutland',          'VT', 43.6106,  -72.9726),
  ('Hartford',         'CT', 41.7658,  -72.6734),
  ('New Haven',        'CT', 41.3083,  -72.9279),
  ('Philadelphia',     'PA', 39.9526,  -75.1652),
  ('Pittsburgh',       'PA', 40.4406,  -79.9959),
  ('Newark',           'NJ', 40.7357,  -74.1724),
  ('Manchester',       'NH', 42.9956,  -71.4548)
on conflict (name, state) do nothing;
