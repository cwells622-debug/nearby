-- ChadAds: automatic hiding of ads that many people report.
-- Run in the Supabase SQL Editor AFTER step21_reports.sql and step33_status_guard.sql. Safe to run more than once. Deletes nothing.
--
-- RULE: when an active ad has 3 open reports from 3 different members (reasons "Already sold" and "Wrong category or location" do not count,
-- they are not about the ad being bad), its status becomes "hidden" at once. It disappears from the site and the sitemap; the seller still
-- sees it in their own list but cannot bring it back. Dealer ads (from the feed) are never hidden this way.
-- You decide on the admin page (Reports tab): "Put back live" if the reports were wrong, or "Mark handled" / delete the ad if they were right.
-- To change the 3, edit it in the function below and run this file again.

-- 1. The guard from step33 must let this one automatic hide through (members' own edits are still refused).
create or replace function public.listings_protect_hidden()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null and not public.is_admin()
     and coalesce(current_setting('app.auto_hide', true), '') <> '1'
     and new.status is distinct from old.status
     and (old.status = 'hidden' or new.status = 'hidden') then
    raise exception 'Only an administrator can hide an ad or make a hidden ad visible again.';
  end if;
  return new;
end;
$$;

-- 2. After each new report: count the open reports on that ad and hide it at 3.
create or replace function public.report_auto_hide()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  if new.listing_id is null or new.reason in ('sold', 'wrong') then return new; end if;
  select count(*) into n from public.reports
   where listing_id = new.listing_id and status = 'open' and reason not in ('sold', 'wrong');
  if n >= 3 then
    perform set_config('app.auto_hide', '1', true);   -- true = only for this one statement/transaction
    update public.listings l set status = 'hidden'
     where l.id = new.listing_id and l.status = 'active'
       and not exists (select 1 from public.profiles p where p.id = l.seller_id and p.is_dealer);
    perform set_config('app.auto_hide', '', true);
  end if;
  return new;
end;
$$;
drop trigger if exists reports_auto_hide on public.reports;
create trigger reports_auto_hide after insert on public.reports
  for each row execute function public.report_auto_hide();
