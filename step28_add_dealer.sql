-- ChadAds: "Add a dealer" from the admin page (no Supabase dashboard, no invite, no login for the dealer).
-- Run in the Supabase SQL Editor AFTER step23_dealer_feed.sql, step25_feed_upload.sql and step26_dealer_website.sql. Safe to run more than once.
--
-- The admin page sends the dealer's details to the importer. The importer creates a placeholder account (an address like
-- dealer-1035978@chadads.com with a long random password nobody knows; it is never used to log in), then calls this function to mark it as a dealer,
-- link the DealerID, name, town and website, and turn email alerts OFF for it. Only the importer (service role) can call it.

create or replace function public.feed_add_dealer(p_source text, p_code text, p_email text, p_name text, p_city text, p_state text, p_website text default null)
returns text
language plpgsql
security definer
set search_path = public, private
as $$
declare sid bigint; uid uuid; cid bigint; site text := nullif(btrim(coalesce(p_website, '')), '');
begin
  select id into sid from private.feed_sources where name = p_source;
  if sid is null then raise exception 'There is no feed called "%". Add the feed first (step23_dealer_feed.sql, section 6, step A).', p_source; end if;
  select id into uid from auth.users where lower(email) = lower(p_email);
  if uid is null then raise exception 'The account for % could not be found.', p_email; end if;
  select id into cid from public.cities where name = p_city and state = upper(p_state);
  if cid is null then raise exception 'The town "%, %" is not in the city list. Check the spelling (for example "Cohasset" and "MA").', p_city, p_state; end if;
  if site is not null and site !~* '^https?://[^[:space:]]+$' then raise exception 'The website must start with https:// (got "%").', site; end if;
  update public.profiles set is_dealer = true, display_name = left(p_name, 40), dealer_website = coalesce(site, dealer_website) where id = uid;
  if lower(p_email) like 'dealer-%@chadads.com' then   -- a placeholder account: nobody reads its mail, so no alert emails
    insert into public.email_prefs (user_id, alerts) values (uid, false) on conflict (user_id) do update set alerts = false;
  end if;
  insert into private.feed_dealers (source_id, dealer_code, seller_id, dealer_name, city_id)
  values (sid, p_code, uid, p_name, cid)
  on conflict (source_id, dealer_code) do update
    set seller_id = excluded.seller_id, dealer_name = excluded.dealer_name, city_id = excluded.city_id, active = true;
  return 'Added: DealerID ' || p_code || ' = ' || p_name || ', ' || p_city || ', ' || upper(p_state) || coalesce(', website ' || site, ', no website yet');
end;
$$;
revoke execute on function public.feed_add_dealer(text, text, text, text, text, text, text) from public, anon, authenticated;
grant  execute on function public.feed_add_dealer(text, text, text, text, text, text, text) to service_role;
