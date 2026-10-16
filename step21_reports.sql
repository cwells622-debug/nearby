-- ChadAds: "Report this ad" (people flag a problem ad; admins review the reports on the admin page).
-- Run in the Supabase SQL Editor AFTER step8_admin.sql (is_admin) and step20_email_alerts.sql (the email key). Safe to run more than once. Deletes nothing.
--
-- RULES
--   * You must be logged in to report. One report per person per ad. At most 10 reports per person per day.
--   * You can't report your own ad. Only active ads can be reported.
--   * The reporter's name is shown only to admins. The seller is NOT told who reported them.
--   * Reports are kept for your records. Admins mark them "resolved" or "dismissed".
--   * Each new report sends YOU an email (to hello@chadads.com, or to the address saved as 'admin_email' in private.app_secrets),
--     sent the same way as message alerts. It needs the Resend key from step20; without it, reports still work, just without the email.

create table if not exists public.reports (
  id            bigint generated always as identity primary key,
  -- If the ad is deleted later, the report stays (listing_id becomes empty) and keeps the title below.
  listing_id    bigint references public.listings (id) on delete set null,
  listing_title text not null default '',
  reporter_id   uuid not null references public.profiles (id) on delete cascade,
  reason        text not null check (reason in ('scam','prohibited','spam','wrong','misleading','offensive','sold','other')),
  details       text not null default '' check (char_length(details) <= 500),
  status        text not null default 'open' check (status in ('open','resolved','dismissed')),
  created_at    timestamptz not null default now(),
  resolved_at   timestamptz
);
create unique index if not exists reports_one_per_person on public.reports (listing_id, reporter_id) where listing_id is not null;
create index if not exists reports_status_idx on public.reports (status, created_at desc);

alter table public.reports enable row level security;

-- Report: only as yourself, only an active ad that is not yours.
drop policy if exists "users report ads" on public.reports;
create policy "users report ads" on public.reports for insert
  with check (
    reporter_id = auth.uid()
    and status = 'open'
    and exists (select 1 from public.listings l
                where l.id = reports.listing_id and l.status = 'active'
                  and l.seller_id is distinct from auth.uid()));

-- Read: your own reports, and everything for admins.
drop policy if exists "read reports" on public.reports;
create policy "read reports" on public.reports for select
  using (reporter_id = auth.uid() or public.is_admin());

-- Change (resolve / dismiss): admins only.
drop policy if exists "admins update reports" on public.reports;
create policy "admins update reports" on public.reports for update
  using (public.is_admin()) with check (public.is_admin());

-- Before saving: copy the ad's real title and enforce the daily limit.
create or replace function public.report_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.reports where reporter_id = new.reporter_id and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'You have sent a lot of reports today. Please try again tomorrow.';
  end if;
  select l.title into new.listing_title from public.listings l where l.id = new.listing_id;
  new.listing_title := coalesce(new.listing_title, '');
  new.details := btrim(new.details);
  return new;
end;
$$;
drop trigger if exists reports_bi on public.reports;
create trigger reports_bi before insert on public.reports
  for each row execute function public.report_before_insert();

-- After saving: email the admin (never blocks the report if anything goes wrong).
create or replace function public.report_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  k text; adm text; rname text; label text; subj text; txt text; html text; n int;
begin
  begin
    select value into k from private.app_secrets where name = 'resend_api_key';
    if k is null or k = '' then return new; end if;
    select value into adm from private.app_secrets where name = 'admin_email';
    adm := coalesce(nullif(adm, ''), 'hello@chadads.com');
    select display_name into rname from public.profiles where id = new.reporter_id;
    select count(*) into n from public.reports where listing_id = new.listing_id and status = 'open';
    label := case new.reason when 'scam' then 'Scam or fraud' when 'prohibited' then 'Prohibited or illegal item'
               when 'spam' then 'Spam or duplicate' when 'wrong' then 'Wrong category or location'
               when 'misleading' then 'Misleading price or details' when 'offensive' then 'Offensive content'
               when 'sold' then 'Already sold' else 'Something else' end;
    subj := 'Report: ' || label || ' - ' || left(new.listing_title, 60);
    txt := 'A new report on ChadAds.' || E'\n\nAd: ' || new.listing_title || ' (#' || new.listing_id || ')'
        || E'\nReason: ' || label || E'\nFrom: ' || coalesce(nullif(btrim(rname), ''), 'a member')
        || case when new.details <> '' then E'\nDetails: ' || new.details else '' end
        || E'\nOpen reports on this ad: ' || n
        || E'\n\nView the ad: https://chadads.com/ad/' || new.listing_id || E'\nReview reports: https://chadads.com/admin.html\n';
    html := '<div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:520px;margin:0 auto;padding:16px;color:#1e1c19">'
      || '<p style="font-size:18px;font-weight:800;color:#e95e0d;margin:0 0 12px">ChadAds report</p>'
      || '<p style="margin:0 0 6px"><strong>' || private.html_escape(new.listing_title) || '</strong> (#' || new.listing_id || ')</p>'
      || '<p style="margin:0 0 6px">Reason: <strong>' || private.html_escape(label) || '</strong></p>'
      || '<p style="margin:0 0 6px">From: ' || private.html_escape(coalesce(nullif(btrim(rname), ''), 'a member')) || '</p>'
      || case when new.details <> '' then '<p style="margin:0 0 6px;background:#f4efe4;padding:10px 12px;border-radius:10px">' || private.html_escape(new.details) || '</p>' else '' end
      || '<p style="margin:0 0 14px;color:#5b5446">Open reports on this ad: ' || n || '</p>'
      || '<p style="margin:0"><a href="https://chadads.com/ad/' || new.listing_id || '">View the ad</a> &nbsp;|&nbsp; <a href="https://chadads.com/admin.html">Review reports</a></p></div>';
    perform net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
      body    := jsonb_build_object('from', 'ChadAds <notifications@chadads.com>', 'to', jsonb_build_array(adm),
                                    'subject', subj, 'html', html, 'text', txt));
  exception when others then
    null;
  end;
  return new;
end;
$$;
drop trigger if exists reports_ai on public.reports;
create trigger reports_ai after insert on public.reports
  for each row execute function public.report_after_insert();

-- Check (optional): open reports, newest first.
-- select r.id, r.listing_id, r.listing_title, r.reason, r.details, p.display_name as reporter, r.created_at
-- from public.reports r join public.profiles p on p.id = r.reporter_id where r.status = 'open' order by r.created_at desc;
