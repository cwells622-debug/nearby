-- Nearby: private messages between buyers and sellers (and offers, which are messages with an amount)
-- Run this in the Supabase SQL Editor AFTER schema.sql. Safe to run more than once. It deletes nothing.
--
-- HOW IT FITS TOGETHER
--   conversations = one row per (ad, buyer). Like a "thread" in an email program.
--   messages      = the individual messages inside a thread. An OFFER is just a message with an amount.
-- PRIVACY: only the buyer and the seller of a thread can see or add to it. Nobody else can, signed in or not.

-- =====================================================================
-- 1. TABLES
-- =====================================================================
create table if not exists public.conversations (
  id                 bigint generated always as identity primary key,
  -- If the ad is deleted later, the conversation stays (listing_id becomes empty) and keeps the title below.
  listing_id         bigint references public.listings (id) on delete set null,
  listing_title      text not null default '',
  buyer_id           uuid not null references public.profiles (id) on delete cascade,
  seller_id          uuid not null references public.profiles (id) on delete cascade,
  created_at         timestamptz not null default now(),
  -- These four are kept up to date by the database itself (see the trigger below), to drive the inbox and "unread" dot.
  last_message_at    timestamptz not null default now(),
  last_sender_id     uuid,
  last_preview       text not null default '',
  buyer_last_read_at  timestamptz,
  seller_last_read_at timestamptz,
  check (buyer_id <> seller_id)
);
-- One thread per buyer per ad.
create unique index if not exists conversations_listing_buyer_uq on public.conversations (listing_id, buyer_id);
create index if not exists conversations_buyer_idx  on public.conversations (buyer_id,  last_message_at desc);
create index if not exists conversations_seller_idx on public.conversations (seller_id, last_message_at desc);

create table if not exists public.messages (
  id              bigint generated always as identity primary key,
  conversation_id bigint not null references public.conversations (id) on delete cascade,
  sender_id       uuid   not null references public.profiles (id) on delete cascade,
  body            text   not null check (char_length(btrim(body)) between 1 and 2000),
  -- Set only on offers (whole dollars).
  offer_amount    integer check (offer_amount is null or (offer_amount > 0 and offer_amount <= 10000000)),
  created_at      timestamptz not null default now()
);
create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at);

-- =====================================================================
-- 2. PRIVACY RULES (row-level security)
-- =====================================================================
alter table public.conversations enable row level security;
alter table public.messages      enable row level security;

-- Read: only the two people in the thread.
drop policy if exists "participants read conversations" on public.conversations;
create policy "participants read conversations"
  on public.conversations for select
  using (auth.uid() in (buyer_id, seller_id));

-- Start a thread: you must be the buyer, the ad must be active, the seller must really be the ad's seller,
-- and you can't message yourself. (There is no update or delete rule on purpose: the database maintains the
-- thread's details itself, and threads are not deleted from the website.)
drop policy if exists "buyers start conversations" on public.conversations;
create policy "buyers start conversations"
  on public.conversations for insert
  with check (
    buyer_id = auth.uid()
    and seller_id <> auth.uid()
    and exists (select 1 from public.listings l
                where l.id = conversations.listing_id
                  and l.seller_id = conversations.seller_id
                  and l.status = 'active'));

-- Messages: read only inside your own threads.
drop policy if exists "participants read messages" on public.messages;
create policy "participants read messages"
  on public.messages for select
  using (exists (select 1 from public.conversations c
                 where c.id = messages.conversation_id
                   and auth.uid() in (c.buyer_id, c.seller_id)));

-- Write: only as yourself, only inside your own threads, and only the BUYER can make an offer.
drop policy if exists "participants send messages" on public.messages;
create policy "participants send messages"
  on public.messages for insert
  with check (
    sender_id = auth.uid()
    and exists (select 1 from public.conversations c
                where c.id = messages.conversation_id
                  and auth.uid() in (c.buyer_id, c.seller_id)
                  and (messages.offer_amount is null or c.buyer_id = auth.uid())));

-- =====================================================================
-- 3. AUTOMATIC BOOKKEEPING AND SPAM LIMITS (triggers = code the database runs by itself)
-- =====================================================================
-- New thread: copy the ad's real title (so it can't be faked) and allow at most 20 new threads per day.
create or replace function public.conversation_before_insert()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.conversations
      where buyer_id = new.buyer_id and created_at > now() - interval '24 hours') >= 20 then
    raise exception 'You have started a lot of conversations today. Please try again tomorrow.';
  end if;
  select l.title into new.listing_title from public.listings l where l.id = new.listing_id;
  new.listing_title := coalesce(new.listing_title, '');
  return new;
end;
$$;
drop trigger if exists conversations_bi on public.conversations;
create trigger conversations_bi before insert on public.conversations
  for each row execute function public.conversation_before_insert();

-- New message: at most 60 per hour per person.
create or replace function public.message_before_insert()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.messages
      where sender_id = new.sender_id and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'You are sending messages very quickly. Please wait a little and try again.';
  end if;
  return new;
end;
$$;
drop trigger if exists messages_bi on public.messages;
create trigger messages_bi before insert on public.messages
  for each row execute function public.message_before_insert();

-- After a message is saved: update the thread's "last message" details, and count the sender as having read it.
-- "security definer" lets this one function update the thread even though people have no update rule.
create or replace function public.message_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations c
  set last_message_at = new.created_at,
      last_sender_id  = new.sender_id,
      last_preview    = left(case when new.offer_amount is not null
                                  then 'Offer: $' || new.offer_amount || ' - ' else '' end || new.body, 100),
      buyer_last_read_at  = case when new.sender_id = c.buyer_id  then new.created_at else c.buyer_last_read_at  end,
      seller_last_read_at = case when new.sender_id = c.seller_id then new.created_at else c.seller_last_read_at end
  where c.id = new.conversation_id;
  return new;
end;
$$;
drop trigger if exists messages_ai on public.messages;
create trigger messages_ai after insert on public.messages
  for each row execute function public.message_after_insert();

-- Called by the page when you open a thread: marks it read for YOU only.
create or replace function public.mark_conversation_read(cid bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations c
  set buyer_last_read_at  = case when c.buyer_id  = auth.uid() then now() else c.buyer_last_read_at  end,
      seller_last_read_at = case when c.seller_id = auth.uid() then now() else c.seller_last_read_at end
  where c.id = cid and auth.uid() in (c.buyer_id, c.seller_id);
end;
$$;
revoke execute on function public.mark_conversation_read(bigint) from public, anon;
grant  execute on function public.mark_conversation_read(bigint) to authenticated;
