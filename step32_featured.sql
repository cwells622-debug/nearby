-- ChadAds: "Featured" ads (premium placement). An administrator ticks a box on the admin page's edit window.
-- Run in the Supabase SQL Editor AFTER step8_admin.sql and step30_browse_ads.sql. Safe to run more than once. Deletes nothing.
--
-- A featured ad is shown FIRST in the listings (home page, category pages, the "nearby" and "newest" orders), with a "Featured" badge on its card
-- and in its pop-up. Only an administrator can change this setting: a member editing their own ad cannot feature it. (You, in the SQL Editor,
-- and the dealer importer are allowed too.)

alter table public.listings add column if not exists featured boolean not null default false;
create index if not exists listings_featured_idx on public.listings (featured) where featured;

-- The guard: only admins (or you in the SQL Editor / the importer, who have no member login) may set or change "featured".
create or replace function public.listings_protect_featured()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.featured := false;
    elsif new.featured is distinct from old.featured then
      raise exception 'Only an administrator can change an ad''s featured setting.';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists listings_protect_featured on public.listings;
create trigger listings_protect_featured before insert or update on public.listings
  for each row execute function public.listings_protect_featured();

-- The ad finder (from step30) now puts featured ads first in the "best", "new" and "near" orders.
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


grant execute on function public.browse_ads(text, bigint, text, double precision, double precision, double precision, text, text, bigint[], int, int, int) to anon, authenticated;

-- Make an ad featured by hand:   update public.listings set featured = true where id = 48;
-- See the featured ads:          select id, title from public.listings where featured;
