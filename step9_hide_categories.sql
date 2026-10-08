-- Nearby: hide seven categories and remove their demo ads
-- Run this in the Supabase SQL Editor. Safe to run more than once.
--
-- "Hiding" keeps the category rows in the database but removes them from the
-- website's menus and from the Post an ad form. To bring one back later:
--   update public.categories set active = true where name = 'Jobs';

-- 1. A switch on each category. Everything stays visible unless you turn it off.
alter table public.categories add column if not exists active boolean not null default true;

-- 2. Hide the seven categories.
update public.categories
set active = false
where name in ('Jobs', 'Property', 'Real Estate', 'Furniture', 'Clothing', 'Appliances', 'Electronics');

-- 3. Delete the DEMO ads that were sitting in those categories (13 sample ads).
--    Demo ads have no photos, so nothing is left behind in storage.
--    Ads posted by real users are NOT touched here. Delete those from the admin
--    page (admin.html), which also removes their photo files.
delete from public.listings
where is_demo
  and category_id in (select id from public.categories where not active);

-- To check what is left in hidden categories (should only be real users' ads):
-- select l.id, l.title, c.name from public.listings l join public.categories c on c.id = l.category_id where not c.active;
