-- Nearby: let admins upload small photo copies for other people's ads
-- Run in the Supabase SQL Editor AFTER step4_photos_and_limits.sql and step8_admin.sql.
-- Safe to run more than once. It deletes nothing.
--
-- Every photo gets a small copy (about 600 px wide) that the home page and lists use, so pages load much faster.
-- New uploads make their own. Photos uploaded before this feature need one made for them: the admin page has a
-- button "Create small photo copies" that does it in one go. Because those photos live in each seller's own folder,
-- the button needs this permission (normal users still cannot write outside their own folder).

drop policy if exists "admins upload any photo file" on storage.objects;
create policy "admins upload any photo file"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'listing-photos' and public.is_admin());
