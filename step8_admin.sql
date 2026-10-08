-- Nearby: admin role (lets chosen accounts edit and remove ANY ad)
-- Run this in the Supabase SQL Editor. Safe to run more than once.
-- It never deletes any of your data.
--
-- HOW IT WORKS
-- Admins are listed in their own small table. Nobody can read or change that
-- table from the website (no policies on purpose), so no user can make
-- themselves an admin. Only you, in the Supabase dashboard, can add one.
-- (Why not a column on "profiles"? Because users are allowed to edit their own
-- profile, so they could flip it themselves.)

-- 1. The list of admins.
create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.admins enable row level security;
-- No policies on purpose: the website can never read or write this table.

-- 2. A yes/no question the rest of the rules can ask: "is the signed-in user an admin?"
--    "security definer" lets it look inside the locked admins table.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- 3. What admins may do. These rules are ADDED to the existing ones, so
--    normal users keep exactly the same limits as before.

-- See every ad, including sold ones.
drop policy if exists "admins read all listings" on public.listings;
create policy "admins read all listings"
  on public.listings for select
  using (public.is_admin());

-- Edit any ad.
drop policy if exists "admins update any listing" on public.listings;
create policy "admins update any listing"
  on public.listings for update
  using (public.is_admin())
  with check (public.is_admin());

-- Delete any ad.
drop policy if exists "admins delete any listing" on public.listings;
create policy "admins delete any listing"
  on public.listings for delete
  using (public.is_admin());

-- Remove any photo row.
drop policy if exists "admins delete any photo row" on public.listing_photos;
create policy "admins delete any photo row"
  on public.listing_photos for delete
  using (public.is_admin());

-- Delete any photo FILE from storage.
drop policy if exists "admins delete any photo file" on storage.objects;
create policy "admins delete any photo file"
  on storage.objects for delete to authenticated
  using (bucket_id = 'listing-photos' and public.is_admin());

-- 4. MAKE YOURSELF AN ADMIN (one time).
--    Replace the email below with the email you signed up to ChadAds with,
--    then run the whole file. If the email doesn't match an account, nothing
--    is added (harmless); fix the email and run again.
insert into public.admins (user_id)
select id from auth.users where email = 'cwells622@gmail.com'
on conflict do nothing;

-- To check: this should list your account.
-- select a.user_id, u.email from public.admins a join auth.users u on u.id = a.user_id;
