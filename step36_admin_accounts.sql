-- ChadAds: an admin tool that lists accounts that were created but never confirmed (the person never clicked the link in the email).
-- Run in the Supabase SQL Editor AFTER step8_admin.sql. Safe to run more than once. Deletes nothing.
--
-- Only an administrator can use it (the function checks). The admin page (Accounts tab) shows email, display name, when they signed up,
-- when the confirmation email was sent, and how many ads they have, with a "Resend email" button. Dealer accounts are left out.

create or replace function public.admin_accounts(p_filter text default 'unconfirmed')
returns table (id uuid, email text, display_name text, created_at timestamptz, confirmation_sent_at timestamptz,
               confirmed_at timestamptz, last_sign_in_at timestamptz, ads bigint)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  return query
    select u.id, u.email::text, p.display_name, u.created_at, u.confirmation_sent_at,
           u.email_confirmed_at, u.last_sign_in_at,
           (select count(*) from public.listings l where l.seller_id = u.id)
    from auth.users u
    left join public.profiles p on p.id = u.id
    where (p_filter = 'all' or u.email_confirmed_at is null)
      and not coalesce(p.is_dealer, false)
    order by u.created_at desc
    limit 500;
end;
$$;
revoke execute on function public.admin_accounts(text) from public, anon;
grant  execute on function public.admin_accounts(text) to authenticated;
