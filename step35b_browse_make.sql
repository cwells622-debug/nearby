-- ChadAds step35 PART B of 3: the ad finder with the make choice, and the make buttons. Run AFTER step35a_make_function.sql.

-- 3. The ad finder (from step32) with one more choice: p_make. The old version is replaced (its list of choices changed).
drop function if exists public.browse_ads(text, bigint, text, double precision, double precision, double precision, text, text, bigint[], int, int, int);

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
  p_offset  int              default 0,
  p_make    text             default null)       -- only this make (Ford, Chevrolet ...) in the car categories
returns table (id bigint, dist double precision, total bigint)
language sql
stable
as $$
  with base as (
    select l.id, l.seller_id, l.category_id, l.created_at, l.price, l.price_on_request, l.featured,
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
      and (p_make is null or l.make = p_make)
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
             case when p_sort in ('best', 'new', 'near') and featured then 0 else 1 end,   -- featured ads first (premium placement)
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

grant execute on function public.browse_ads(text, bigint, text, double precision, double precision, double precision, text, text, bigint[], int, int, int, text) to anon, authenticated;

-- 4. The make buttons: the makes in one category (with counts), for the same filters as the ad list (but not the make itself).
create or replace function public.browse_makes(
  p_cat     bigint,
  p_q       text             default null,
  p_region  text             default null,
  p_lat     double precision default null,
  p_lng     double precision default null,
  p_radius  double precision default 0,
  p_dealer  text             default 'all')
returns table (make text, n bigint)
language sql
stable
as $$
  select l.make, count(*)::bigint
  from public.listings l
  join public.cities c on c.id = l.city_id
  join public.categories cat on cat.id = l.category_id
  left join public.profiles pr on pr.id = l.seller_id
  where l.status = 'active'
    and cat.active
    and l.category_id = p_cat
    and l.make is not null
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
  group by l.make
  order by count(*) desc, l.make
$$;
grant execute on function public.browse_makes(bigint, text, text, double precision, double precision, double precision, text) to anon, authenticated;

