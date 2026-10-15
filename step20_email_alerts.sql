-- ChadAds: email alerts for new messages and offers.
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- It does nothing visible until you finish the setup (NOTES.md, section "Email alerts"): the secret below must be filled in.
--
-- HOW IT WORKS
--   1. A message is saved. A trigger (code the database runs by itself) works out who should be told (the OTHER person in the thread).
--   2. It skips the email if that person switched alerts off, or was already emailed about this thread in the last 15 minutes.
--   3. Otherwise it calls https://chadads.com/api/notify (a small Netlify function) with the details. That function sends the email through Resend.
--   4. If anything goes wrong in steps 1-3, the message is STILL saved normally. An alert can never block a message.
--   The recipient's email address is read inside the database only and is never shown to the sender or put in the web page.

-- 0. Lets the database make web requests (used to call the Netlify function).
create extension if not exists pg_net;

-- 1. A private place for the shared secret. The "private" schema is not reachable from the website.
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

-- 5. The trigger that sends the alert.
create or replace function public.message_notify()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  c record; rid uuid; rmail text; rname text; sname text; tok uuid; sec text; want boolean; last_at timestamptz;
begin
  begin
    select * into c from public.conversations where id = new.conversation_id;
    if not found then return new; end if;
    rid := case when new.sender_id = c.buyer_id then c.seller_id else c.buyer_id end;

    select value into sec from private.app_secrets where name = 'notify_secret';
    if sec is null or sec = '' then return new; end if;   -- not set up yet

    insert into public.email_prefs (user_id) values (rid) on conflict do nothing;
    select alerts, token into want, tok from public.email_prefs where user_id = rid;
    if not want then return new; end if;

    last_at := case when rid = c.buyer_id then c.buyer_alert_at else c.seller_alert_at end;
    if last_at is not null and last_at > now() - interval '15 minutes' then return new; end if;

    select email into rmail from auth.users where id = rid;
    if rmail is null then return new; end if;
    select display_name into rname from public.profiles where id = rid;
    select display_name into sname from public.profiles where id = new.sender_id;

    if rid = c.buyer_id then update public.conversations set buyer_alert_at = now() where id = c.id;
    else update public.conversations set seller_alert_at = now() where id = c.id; end if;

    perform net.http_post(
      url     := 'https://chadads.com/api/notify',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-notify-secret', sec),
      body    := jsonb_build_object(
        'to', rmail, 'toName', coalesce(rname, ''), 'fromName', coalesce(sname, 'Someone'),
        'adTitle', c.listing_title, 'body', left(new.body, 300), 'offer', new.offer_amount,
        'conversationId', c.id,
        'unsubUrl', 'https://chadads.com/unsubscribe?u=' || rid || '&t=' || tok));
  exception when others then
    null;   -- never let an alert problem stop a message from being saved
  end;
  return new;
end;
$$;
drop trigger if exists messages_notify on public.messages;
create trigger messages_notify after insert on public.messages
  for each row execute function public.message_notify();

-- 6. YOUR SECRET (do this once, in the SQL Editor, with your own long random text; it must match NOTIFY_SECRET in Netlify):
--    insert into private.app_secrets (name, value) values ('notify_secret', 'PASTE-YOUR-LONG-RANDOM-TEXT-HERE')
--    on conflict (name) do update set value = excluded.value;
--    Do NOT save the real value in this file or in GitHub. To switch alerts off for everyone:  delete from private.app_secrets where name = 'notify_secret';
--
-- Check (optional): did the website call get an answer?  select id, status_code, content from net._http_response order by id desc limit 5;
