-- ChadAds: email alerts for new messages and offers.
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- It does nothing visible until you store your Resend key (see the bottom of this file).
--
-- HOW IT WORKS
--   1. A message is saved. A trigger (code the database runs by itself) works out who should be told (the OTHER person in the thread).
--   2. It skips the email if that person switched alerts off, or was already emailed about this thread in the last 15 minutes.
--   3. Otherwise it sends the email straight from the database through Resend (resend.com), using the key stored in private.app_secrets.
--   4. If anything goes wrong in steps 1-3, the message is STILL saved normally. An alert can never block a message.
--   The recipient's email address is read inside the database only and is never shown to the sender or put in the web page.

-- 0. Lets the database make web requests (used to call Resend).
create extension if not exists pg_net;

-- 1. A private place for the Resend key. The "private" schema is not reachable from the website.
create schema if not exists private;
create table if not exists private.app_secrets (
  name  text primary key,
  value text not null
);
alter table private.app_secrets enable row level security;   -- no policies = nobody but the database owner can read it
revoke all on private.app_secrets from anon, authenticated;

-- 2. Each person's alert choice. No row means "alerts on". "token" lets an email's Unsubscribe link work without logging in.
create table if not exists public.email_prefs (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  alerts  boolean not null default true,
  token   uuid not null default gen_random_uuid()
);
alter table public.email_prefs enable row level security;
drop policy if exists "read own email prefs" on public.email_prefs;
create policy "read own email prefs" on public.email_prefs for select using (auth.uid() = user_id);
drop policy if exists "add own email prefs" on public.email_prefs;
create policy "add own email prefs" on public.email_prefs for insert with check (auth.uid() = user_id);
drop policy if exists "change own email prefs" on public.email_prefs;
create policy "change own email prefs" on public.email_prefs for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 3. When each person was last emailed about a thread (so a busy conversation does not send an email per message).
alter table public.conversations add column if not exists buyer_alert_at  timestamptz;
alter table public.conversations add column if not exists seller_alert_at timestamptz;

-- 4. The Unsubscribe link in each email calls this (works without logging in, but only with the right token).
create or replace function public.unsubscribe_alerts(p_user uuid, p_token uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.email_prefs set alerts = false where user_id = p_user and token = p_token;
  return found;
end;
$$;
grant execute on function public.unsubscribe_alerts(uuid, uuid) to anon, authenticated;

-- 5. Makes text safe to put inside the email's HTML.
create or replace function private.html_escape(t text)
returns text
language sql
immutable
as $$
  select replace(replace(replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;')
$$;

-- 6. The trigger that sends the alert.
create or replace function public.message_notify()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  c record; rid uuid; rmail text; rname text; sname text; tok uuid; k text; want boolean; last_at timestamptz;
  title text; prev text; amt text; what text; subj text; hi text; link text; unsub text; txt text; html text;
begin
  begin
    select * into c from public.conversations where id = new.conversation_id;
    if not found then return new; end if;
    rid := case when new.sender_id = c.buyer_id then c.seller_id else c.buyer_id end;

    select value into k from private.app_secrets where name = 'resend_api_key';
    if k is null or k = '' then return new; end if;   -- not set up yet

    insert into public.email_prefs (user_id) values (rid) on conflict do nothing;
    select alerts, token into want, tok from public.email_prefs where user_id = rid;
    if not want then return new; end if;

    last_at := case when rid = c.buyer_id then c.buyer_alert_at else c.seller_alert_at end;
    if last_at is not null and last_at > now() - interval '15 minutes' then return new; end if;

    select email into rmail from auth.users where id = rid;
    if rmail is null then return new; end if;
    select display_name into rname from public.profiles where id = rid;
    select display_name into sname from public.profiles where id = new.sender_id;
    sname := left(coalesce(nullif(btrim(sname), ''), 'Someone'), 40);

    if rid = c.buyer_id then update public.conversations set buyer_alert_at = now() where id = c.id;
    else update public.conversations set seller_alert_at = now() where id = c.id; end if;

    title := left(coalesce(nullif(btrim(c.listing_title), ''), 'your ad'), 80);
    prev  := left(regexp_replace(new.body, '\s+', ' ', 'g'), 300);
    amt   := case when new.offer_amount is not null then '$' || to_char(new.offer_amount, 'FM999,999,999') end;
    what  := case when amt is not null then 'an offer of ' || amt else 'a message' end;
    subj  := case when amt is not null then sname || ' offered ' || amt || ' on ' || left(title, 50)
                  else 'New message from ' || sname || ' about ' || left(title, 50) end;
    hi    := case when nullif(btrim(rname), '') is not null then 'Hi ' || left(btrim(rname), 40) || ',' else 'Hi,' end;
    link  := 'https://chadads.com/?messages=' || c.id;
    unsub := 'https://chadads.com/unsubscribe?u=' || rid || '&t=' || tok;

    txt := hi || E'\n\n' || sname || ' sent you ' || what || ' about "' || title || E'" on ChadAds:\n\n'
        || case when amt is not null then 'Offer: ' || amt || E'\n' else '' end || prev
        || E'\n\nRead it and reply on ChadAds: ' || link
        || E'\n\nPlease reply on ChadAds. Replying to this email will not reach them.'
        || E'\n\nDon''t want these emails? Turn them off: ' || unsub || E'\n';

    html := '<!doctype html><html><body style="margin:0;background:#f4efe4;font-family:-apple-system,BlinkMacSystemFont,''Segoe UI'',Roboto,Helvetica,Arial,sans-serif;color:#1e1c19">'
      || '<div style="max-width:520px;margin:0 auto;padding:24px 16px"><div style="background:#fbf7ef;border-radius:16px;padding:28px 24px;border-bottom:6px solid #e95e0d">'
      || '<p style="margin:0 0 16px;font-size:20px;font-weight:800;color:#e95e0d">ChadAds</p>'
      || '<p style="margin:0 0 14px;font-size:16px">' || private.html_escape(hi) || '</p>'
      || '<p style="margin:0 0 14px;font-size:16px"><strong>' || private.html_escape(sname) || '</strong> sent you ' || private.html_escape(what)
      || ' about <strong>' || private.html_escape(title) || '</strong>:</p>'
      || '<div style="background:#fff;border-radius:12px;padding:14px 16px;margin:0 0 20px;font-size:16px;line-height:1.45">'
      || case when amt is not null then '<div style="font-weight:800;color:#e95e0d;margin-bottom:6px">Offer: ' || private.html_escape(amt) || '</div>' else '' end
      || private.html_escape(prev) || '</div>'
      || '<p style="margin:0 0 20px"><a href="' || private.html_escape(link) || '" style="display:inline-block;background:#e95e0d;color:#1e1c19;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:999px">View message</a></p>'
      || '<p style="margin:0;font-size:13px;color:#5b5446">Please reply on ChadAds. Replying to this email will not reach them.</p></div>'
      || '<p style="margin:14px 0 0;font-size:12px;color:#5b5446;text-align:center">Don''t want these emails? <a href="' || private.html_escape(unsub) || '" style="color:#5b5446">Turn them off</a>.</p>'
      || '</div></body></html>';

    perform net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
      body    := jsonb_build_object(
        'from', 'ChadAds <notifications@chadads.com>',
        'to', jsonb_build_array(rmail),
        'subject', subj, 'html', html, 'text', txt,
        'headers', jsonb_build_object('List-Unsubscribe', '<' || unsub || '>')));
  exception when others then
    null;   -- never let an alert problem stop a message from being saved
  end;
  return new;
end;
$$;
drop trigger if exists messages_notify on public.messages;
create trigger messages_notify after insert on public.messages
  for each row execute function public.message_notify();

-- 7. YOUR RESEND KEY (do this once, in the SQL Editor; paste your real key between the quotes; it starts with re_):
--    insert into private.app_secrets (name, value) values ('resend_api_key', 'PASTE-YOUR-RESEND-KEY-HERE')
--    on conflict (name) do update set value = excluded.value;
--    Do NOT save the real key in this file or in GitHub. To switch alerts off for everyone:  delete from private.app_secrets where name = 'resend_api_key';
--
-- Check (optional): did Resend answer?  select id, status_code, content from net._http_response order by id desc limit 5;
-- (status 200 = sent; 401/403 = key or sending address not accepted; 422 = Resend refused the email, the content says why)
