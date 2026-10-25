-- ChadAds: small cleanups (run in the Supabase SQL Editor). Each part checks first and refuses to delete the wrong thing.
--   1. Deletes the leftover test ad #46 "Post an ad" (Free, Albany). Its photo row goes with it.
--   2. Deletes the OLD, unused "Marchese Ford" dealer account (id 854ae1f8...), the one from before the real DealerID was set up.
--      It refuses if that account has ANY ad (the live Marchese Ford account, 9d60eb84..., is never touched).
-- Nothing else is deleted. If a part refuses, it says why and changes nothing.

do $$
declare
  old_id constant uuid := '854ae1f8-8a12-4e33-9677-748754cbec87';
  n int;
begin
  -- 1. the test ad
  delete from public.listings where id = 46 and title = 'Post an ad' and price = 0 and is_demo = false;
  get diagnostics n = row_count;
  raise notice 'Test ad deleted: % row(s)', n;

  -- 2. the unused dealer account
  if not exists (select 1 from public.profiles where id = old_id and is_dealer and display_name = 'Marchese Ford') then
    raise notice 'Old Marchese account not found (already removed?). Nothing done.';
  elsif exists (select 1 from public.listings where seller_id = old_id) then
    raise exception 'The old Marchese account still has ads. Nothing was deleted for it.';
  else
    delete from private.feed_dealers where seller_id = old_id;
    delete from auth.users where id = old_id;   -- also removes its profile
    raise notice 'Old Marchese Ford account deleted.';
  end if;
end $$;

-- Check afterwards: should list Caruso Classics and ONE Marchese Ford.
select display_name, id from public.profiles where is_dealer order by display_name;
