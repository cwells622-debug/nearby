-- Nearby: hide two more categories (Medical, Antiques)
-- Run in the Supabase SQL Editor. Safe to run more than once. Deletes nothing.
-- Neither category had any ads when this was written.
-- To bring one back:  update public.categories set active = true where name = 'Medical';

update public.categories set active = false where name in ('Medical', 'Antiques');
