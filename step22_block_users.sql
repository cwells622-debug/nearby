-- ChadAds: block a member from messaging you.
-- Run in the Supabase SQL Editor AFTER step14_messaging.sql. Safe to run more than once. Deletes nothing.
--
-- RULES
--   * Anyone can block someone they have a conversation with (button in the Messages screen) and unblock them again.
--   * While a block exists, NEITHER person can send new messages or offers to the other, and nobody can start a new conversation between them.
--     (Old messages stay readable. You can't message someone you blocked until you unblock them.)
--   * The blocked person is not told they were blocked. If they try to message you they just see "This member is not accepting messages."
--   * Nothing is emailed to someone for a blocked person, because their messages can't be sent at all.
--   * Only you can see who you blocked.

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
alter table public.blocks enable row level security;
drop policy if exists "read my blocks" on public.blocks;
create policy "read my blocks" on public.blocks for select using (blocker_id = auth.uid());
drop policy if exists "add my blocks" on public.blocks;
create policy "add my blocks" on public.blocks for insert with check (blocker_id = auth.uid());
drop policy if exists "remove my blocks" on public.blocks;
create policy "remove my blocks" on public.blocks for delete using (blocker_id = auth.uid());

-- "me" = I blocked them, "them" = they blocked me, empty = no block. Only ever about the signed-in person and one other member.
create or replace function public.block_state(other uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (select 1 from public.blocks where blocker_id = auth.uid() and blocked_id = other) then 'me'
    when exists (select 1 from public.blocks where blocker_id = other and blocked_id = auth.uid()) then 'them'
  end
$$;
revoke execute on function public.block_state(uuid) from public, anon;
grant  execute on function public.block_state(uuid) to authenticated;

-- Starting a conversation: refuse if there is a block between the two people (same 20-a-day limit and title copy as before).
create or replace function public.conversation_before_insert()
returns trigger
language plpgsql
as $$
declare bs text;
begin
  bs := public.block_state(case when new.buyer_id = auth.uid() then new.seller_id else new.buyer_id end);
  if bs = 'me' then raise exception 'You have blocked this member. Unblock them in your Messages to contact them.'; end if;
  if bs = 'them' then raise exception 'This member is not accepting messages.'; end if;
  if (select count(*) from public.conversations
      where buyer_id = new.buyer_id and created_at > now() - interval '24 hours') >= 20 then
    raise exception 'You have started a lot of conversations today. Please try again tomorrow.';
  end if;
  select l.title into new.listing_title from public.listings l where l.id = new.listing_id;
  new.listing_title := coalesce(new.listing_title, '');
  return new;
end;
$$;

-- Sending a message or offer: refuse if there is a block (same 60-an-hour limit as before).
create or replace function public.message_before_insert()
returns trigger
language plpgsql
as $$
declare bs text; other uuid;
begin
  select case when c.buyer_id = new.sender_id then c.seller_id else c.buyer_id end into other
  from public.conversations c where c.id = new.conversation_id;
  if other is not null then
    bs := public.block_state(other);
    if bs = 'me' then raise exception 'You have blocked this member. Unblock them to send messages.'; end if;
    if bs = 'them' then raise exception 'This member is not accepting messages.'; end if;
  end if;
  if (select count(*) from public.messages
      where sender_id = new.sender_id and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'You are sending messages very quickly. Please wait a little and try again.';
  end if;
  return new;
end;
$$;

-- Check (optional): who have I blocked (run as yourself in the app, not here).  select * from public.blocks;
