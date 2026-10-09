-- Nearby: switch OFF uploading video files (the YouTube / Vimeo link still works)
-- Run this in the Supabase SQL Editor. Safe to run more than once. It deletes nothing.
--
-- The page no longer shows the upload box. This closes the door on the database side too,
-- so nobody can upload a video file by calling the database directly.
--
-- TO BRING VIDEO UPLOAD BACK later: run step11_video.sql again (it recreates this rule),
-- and remove the word "hidden" from the vidUploadRow line in public/index.html.

drop policy if exists "users upload videos to own folder" on storage.objects;
