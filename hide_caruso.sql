-- ChadAds: pause the Caruso Classics feed (DealerID 1035978) and hide its ads.
-- Run in the Supabase SQL Editor. Deletes nothing: the ads stay in the database with status 'hidden'
-- (off the site and out of the sitemap). To bring them back: set the status back to 'active' and the dealer's active back to true.

-- 1. Look first: how many ads will be hidden? (expect about 52)
select count(*) as ads_to_hide
from public.listings
where status = 'active'
  and seller_id = (select seller_id from private.feed_dealers where dealer_code = '1035978');

-- 2. Stop the importer reading this dealer.
update private.feed_dealers set active = false where dealer_code = '1035978';

-- 3. Hide the dealer's ads.
update public.listings set status = 'hidden'
where status = 'active'
  and seller_id = (select seller_id from private.feed_dealers where dealer_code = '1035978');

-- 4. Check: should show active = false, and 0 active ads.
select d.dealer_name, d.active,
       (select count(*) from public.listings l where l.seller_id = d.seller_id and l.status = 'active') as active_ads,
       (select count(*) from public.listings l where l.seller_id = d.seller_id and l.status = 'hidden') as hidden_ads
from private.feed_dealers d where d.dealer_code = '1035978';
