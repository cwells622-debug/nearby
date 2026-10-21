-- ChadAds: dealer ads link to the dealer's website (dealers never log in) + a SECURITY FIX for the dealer flag.
-- Run in the Supabase SQL Editor AFTER step23_dealer_feed.sql. Safe to run more than once. Deletes nothing.
--
-- 1. Each dealer profile can have a website. On a dealer's ads the "Message" button is replaced by "Visit <dealer>'s website"
--    (with the usual "this link leaves ChadAds" warning). The dealer never needs to log in to answer anything.
-- 2. SECURITY FIX: step23 added profiles.is_dealer, and members may edit their own profile, so a member could have set
--    is_dealer on themselves (which lifts the 10-ads-a-day limit). A guard now allows only an administrator (or you in the
--    SQL Editor) to change is_dealer and dealer_website.

alter table public.profiles add column if not exists dealer_website text;
alter table public.profiles drop constraint if exists profiles_dealer_website_format;
alter table public.profiles add constraint profiles_dealer_website_format
  check (dealer_website is null or (dealer_website ~* '^https?://[^[:space:]]+$' and char_length(dealer_website) <= 300));

create or replace function public.profiles_protect_dealer()
returns trigger
language plpgsql
as $$
begin
  if (new.is_dealer is distinct from old.is_dealer or new.dealer_website is distinct from old.dealer_website)
     and auth.uid() is not null and not public.is_admin() then
    raise exception 'Only an administrator can change dealer settings.';
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_protect_dealer on public.profiles;
create trigger profiles_protect_dealer before update on public.profiles
  for each row execute function public.profiles_protect_dealer();

-- The one-line "add a dealer" now takes an optional website as a 7th piece. (The old 6-piece version is replaced.)
drop function if exists private.add_feed_dealer(text, text, text, text, text, text);
create or replace function private.add_feed_dealer(p_source text, p_code text, p_email text, p_name text, p_city text, p_state text, p_website text default null)
returns text
language plpgsql
as $$
declare sid bigint; uid uuid; cid bigint; site text := nullif(btrim(coalesce(p_website, '')), '');
begin
  select id into sid from private.feed_sources where name = p_source;
  if sid is null then raise exception 'There is no feed called "%". Add it first (step23_dealer_feed.sql, section 6, step A).', p_source; end if;
  select id into uid from auth.users where lower(email) = lower(p_email);
  if uid is null then raise exception 'There is no ChadAds account with the email "%". Create it first (Supabase > Authentication > Users > Add user).', p_email; end if;
  select id into cid from public.cities where name = p_city and state = p_state;
  if cid is null then raise exception 'The town "%, %" is not in the city list.', p_city, p_state; end if;
  if site is not null and site !~* '^https?://[^[:space:]]+$' then raise exception 'The website must start with https:// (got "%").', site; end if;
  update public.profiles set is_dealer = true, display_name = left(p_name, 40), dealer_website = coalesce(site, dealer_website) where id = uid;
  insert into private.feed_dealers (source_id, dealer_code, seller_id, dealer_name, city_id)
  values (sid, p_code, uid, p_name, cid)
  on conflict (source_id, dealer_code) do update
    set seller_id = excluded.seller_id, dealer_name = excluded.dealer_name, city_id = excluded.city_id, active = true;
  return 'OK: DealerID ' || p_code || ' = ' || p_name || ', ' || p_city || ', ' || p_state || ' (account ' || p_email || ')' || coalesce(', website ' || site, ', no website yet');
end;
$$;
revoke all on function private.add_feed_dealer(text, text, text, text, text, text, text) from public, anon, authenticated;

-- Examples (replace the capital-letter parts; the website must start with https://):
--   select private.add_feed_dealer('carsforsale.com', '1035978', 'ACCOUNT-EMAIL', 'Caruso Classics', 'Cohasset', 'MA', 'https://THEIR-WEBSITE');
--   Set or change a website later:  update public.profiles set dealer_website = 'https://THEIR-WEBSITE' where display_name = 'Marchese Ford' and is_dealer;
