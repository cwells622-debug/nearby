-- ChadAds: find ads in the database, a page at a time (so the home page no longer loads every ad at once).
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
--
-- browse_ads()    : the ids of the ads to show (one page), in the right order, plus the total number that match.
-- browse_counts() : how many ads match in each category (for the numbers next to the category buttons).
--
-- THE DEFAULT ORDER ("best"): nearby first, then fair between sellers.
--   1. Ads close to the visitor first (within 100 miles, then within 250 miles, then the rest). Without a chosen city the centre is
--      the Albany area (the page sends it), so Capital Region ads come before ads from far away.
--   2. Inside that, sellers take turns: every seller's newest ad, then every seller's second newest, and so on. So one dealer with 300 cars
--      cannot push everyone else's ads out of sight.
--   3. Then newest first.
-- Other orders: new, old, low (price), high (price), near (distance). "Call for price" ads go last in the price orders.
-- Only ads that are active (and in a visible category) are returned, the same as the website always showed.

create or replace function public.browse_ads(
  p_q       text             default null,
  p_cat     bigint           default null,
  p_region  text             default null,
  p_lat     double precision default null,
  p_lng     double precision default null,
  p_radius  double precision default 0,
  p_sort    text             default 'best',
  p_dealer  text             default 'all',      -- 'all', 'private' or 'dealer'
  p_ids     bigint[]         default null,       -- only these ads (the Saved view)
  p_per_cat int              default null,       -- keep only the first N of each category (the "By category" view)
  p_limit   int              default 48,
  p_offset  int              default 0)
returns table (id bigint, dist double precision, total bigint)
language sql
stable
as $$
  with base as (
    select l.id, l.seller_id, l.category_id, l.created_at, l.price, l.price_on_request,
           case when p_lat is null or p_lng is null then null::double precision
                else 3959 * 2 * asin(sqrt(least(1.0,
                       power(sin(radians(c.lat - p_lat) / 2), 2)
                       + cos(radians(p_lat)) * cos(radians(c.lat)) * power(sin(radians(c.lng - p_lng) / 2), 2)))) end as dist
    from public.listings l
    join public.cities c on c.id = l.city_id
    join public.categories cat on cat.id = l.category_id
    left join public.profiles pr on pr.id = l.seller_id
    where l.status = 'active'
      and cat.active
      and (p_cat is null or l.category_id = p_cat)
      and (p_region is null or p_region = any (c.regions))
      and (p_ids is null or l.id = any (p_ids))
      and (coalesce(p_dealer, 'all') = 'all'
           or (p_dealer = 'dealer' and coalesce(pr.is_dealer, false))
           or (p_dealer = 'private' and not coalesce(pr.is_dealer, false)))
      and (coalesce(btrim(p_q), '') = ''
           or l.title ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
           or l.description ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
           or c.name ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%')
  ),
  near as (
    select * from base
    where coalesce(p_radius, 0) <= 0 or p_lat is null or dist <= p_radius
  ),
  turns as (
    select *,
           row_number() over (partition by seller_id order by created_at desc, id desc) as turn,
           case when dist is null then 0 when dist <= 100 then 0 when dist <= 250 then 1 else 2 end as bucket
    from near
  ),
  ordered as (
    select *,
           row_number() over (order by
             case when p_sort = 'best' then bucket end,
             case when p_sort = 'best' then turn end,
             case when p_sort = 'low'  then (case when price_on_request then 1e12 else price end) end,
             case when p_sort = 'high' then (case when price_on_request then -1 else price end) end desc,
             case when p_sort = 'near' then dist end,
             case when p_sort = 'old'  then created_at end,
             created_at desc, id desc) as pos
    from turns
  ),
  per_cat as (
    select *, row_number() over (partition by category_id order by pos) as cat_pos from ordered
  ),
  picked as (
    select id, dist, pos, count(*) over () as total
    from per_cat
    where p_per_cat is null or cat_pos <= p_per_cat
  )
  select id, dist, total from picked order by pos limit greatest(p_limit, 0) offset greatest(p_offset, 0)
$$;

create or replace function public.browse_counts(
  p_q       text             default null,
  p_region  text             default null,
  p_lat     double precision default null,
  p_lng     double precision default null,
  p_radius  double precision default 0,
  p_dealer  text             default 'all')
returns table (category_id bigint, n bigint)
language sql
stable
as $$
  select l.category_id, count(*)::bigint
  from public.listings l
  join public.cities c on c.id = l.city_id
  join public.categories cat on cat.id = l.category_id
  left join public.profiles pr on pr.id = l.seller_id
  where l.status = 'active'
    and cat.active
    and (p_region is null or p_region = any (c.regions))
    and (coalesce(p_dealer, 'all') = 'all'
         or (p_dealer = 'dealer' and coalesce(pr.is_dealer, false))
         or (p_dealer = 'private' and not coalesce(pr.is_dealer, false)))
    and (coalesce(p_radius, 0) <= 0 or p_lat is null or p_lng is null
         or 3959 * 2 * asin(sqrt(least(1.0,
              power(sin(radians(c.lat - p_lat) / 2), 2)
              + cos(radians(p_lat)) * cos(radians(c.lat)) * power(sin(radians(c.lng - p_lng) / 2), 2)))) <= p_radius)
    and (coalesce(btrim(p_q), '') = ''
         or l.title ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
         or l.description ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
         or c.name ilike '%' || replace(replace(replace(btrim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%')
  group by l.category_id
$$;

grant execute on function public.browse_ads(text, bigint, text, double precision, double precision, double precision, text, text, bigint[], int, int, int) to anon, authenticated;
grant execute on function public.browse_counts(text, text, double precision, double precision, double precision, text) to anon, authenticated;

-- Try it (these return the first ads the home page would show):
--   select * from public.browse_ads();
--   select * from public.browse_ads(p_q => 'ford', p_sort => 'low');
--   select * from public.browse_counts();
