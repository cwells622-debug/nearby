-- One-time tidy: remove the sentence " Message us on ChadAds to ask about this vehicle."
-- from the end of dealer ad descriptions, leaving "Sold by <dealer>, <town>."
-- Only dealer ads that contain the exact sentence are touched; nothing is deleted.
-- Safe to run more than once.

update public.listings l
set description = regexp_replace(l.description, ' Message us on ChadAds to ask about this vehicle\.', '')
from public.profiles p
where p.id = l.seller_id
  and p.is_dealer
  and l.description like '%Message us on ChadAds to ask about this vehicle.%';

-- How many dealer ads still have the sentence (should be 0):
select count(*) as still_have_it
from public.listings
where description like '%Message us on ChadAds to ask about this vehicle.%';
