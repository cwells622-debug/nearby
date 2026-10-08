-- Nearby: video on ads (short uploaded clips + YouTube/Vimeo links)
-- Run this in the Supabase SQL Editor AFTER step4_photos_and_limits.sql and step8_admin.sql.
-- Safe to run more than once. It never deletes any of your data.
--
-- NOTE ON SIZE: this asks for a 50 MB limit per video. Supabase's FREE plan has its own
-- project-wide cap on file size (50 MB). If a larger number is ever needed, check
-- Supabase Dashboard -> Storage -> Settings, and the plan limits.

-- =====================================================================
-- 1. STORAGE BUCKET FOR VIDEO FILES
-- =====================================================================
-- Same idea as the photo bucket: anyone can WATCH a video if the page shows it;
-- only the owner can upload or delete, inside their own folder (<user id>/<random>.mp4).
-- The bucket itself refuses anything that isn't MP4, MOV or WebM, or is over 50 MB.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-videos', 'listing-videos', true, 52428800,
        array['video/mp4', 'video/quicktime', 'video/webm'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "users upload videos to own folder" on storage.objects;
create policy "users upload videos to own folder"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'listing-videos'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users update videos in own folder" on storage.objects;
create policy "users update videos in own folder"
  on storage.objects for update to authenticated
  using (bucket_id = 'listing-videos'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users delete videos in own folder" on storage.objects;
create policy "users delete videos in own folder"
  on storage.objects for delete to authenticated
  using (bucket_id = 'listing-videos'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "admins delete any video file" on storage.objects;
create policy "admins delete any video file"
  on storage.objects for delete to authenticated
  using (bucket_id = 'listing-videos' and public.is_admin());

-- =====================================================================
-- 2. TABLE THAT CONNECTS A VIDEO FILE TO AN AD (like listing_photos)
-- =====================================================================
create table if not exists public.listing_videos (
  id           bigint generated always as identity primary key,
  listing_id   bigint not null references public.listings (id) on delete cascade,
  storage_path text not null
);
create index if not exists listing_videos_listing_idx on public.listing_videos (listing_id);

alter table public.listing_videos enable row level security;

-- You can see a video if you can see its ad.
drop policy if exists "videos visible with their listing" on public.listing_videos;
create policy "videos visible with their listing"
  on public.listing_videos for select
  using (exists (select 1 from public.listings l where l.id = listing_id));

-- You can attach a video only to your own ad, and only a file from your own folder.
drop policy if exists "users add videos to own listings" on public.listing_videos;
create policy "users add videos to own listings"
  on public.listing_videos for insert
  with check (
    storage_path like auth.uid()::text || '/%'
    and exists (select 1 from public.listings l
                where l.id = listing_id and l.seller_id = auth.uid()));

drop policy if exists "users delete videos from own listings" on public.listing_videos;
create policy "users delete videos from own listings"
  on public.listing_videos for delete
  using (exists (select 1 from public.listings l
                 where l.id = listing_id and l.seller_id = auth.uid()));

drop policy if exists "admins delete any video row" on public.listing_videos;
create policy "admins delete any video row"
  on public.listing_videos for delete
  using (public.is_admin());

-- At most 1 uploaded video per ad.
create or replace function public.limit_videos_per_listing()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.listing_videos
      where listing_id = new.listing_id) >= 1 then
    raise exception 'An ad can have 1 uploaded video.';
  end if;
  return new;
end;
$$;

drop trigger if exists listing_videos_limit on public.listing_videos;
create trigger listing_videos_limit
  before insert on public.listing_videos
  for each row execute function public.limit_videos_per_listing();

-- =====================================================================
-- 3. YOUTUBE / VIMEO LINK ON AN AD
-- =====================================================================
-- Only addresses from YouTube or Vimeo are accepted (these are the only sites the page
-- will ever embed), so nobody can sneak in another site or a "javascript:" address.
alter table public.listings add column if not exists video_link text;

alter table public.listings drop constraint if exists listings_video_link_format;
alter table public.listings add constraint listings_video_link_format
  check (video_link is null or (
    char_length(video_link) <= 200
    and video_link ~* '^https://(www\.|m\.)?(youtube\.com/(watch\?v=|shorts/|embed/)|youtu\.be/|vimeo\.com/)[A-Za-z0-9_?=&/.-]+$'));
