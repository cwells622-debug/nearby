-- ChadAds: SECURITY FIX. A member could set an ad you had hidden back to "active" (members may edit their own ads, status included).
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
--
-- New rule: only an administrator can set an ad to "hidden" or bring a hidden ad back. Members can still switch their own ads between
-- "active" and "sold". You (in the SQL Editor) and the dealer importer have no member login, so they are not affected.

create or replace function public.listings_protect_hidden()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null and not public.is_admin()
     and new.status is distinct from old.status
     and (old.status = 'hidden' or new.status = 'hidden') then
    raise exception 'Only an administrator can hide an ad or make a hidden ad visible again.';
  end if;
  return new;
end;
$$;
drop trigger if exists listings_protect_hidden on public.listings;
create trigger listings_protect_hidden before update on public.listings
  for each row execute function public.listings_protect_hidden();
