-- ChadAds: run the dealer feed importer automatically (every hour at 20 minutes past).
-- Run in the Supabase SQL Editor ONLY AFTER: step23_dealer_feed.sql is run, the "import-feed" function is deployed (with "Verify JWT" OFF),
-- the 'import_secret' is saved (bottom of step23), and a Preview from the admin page looked right.
-- Safe to run more than once (it replaces the schedule). The importer skips cars that have not changed, so running often is cheap;
-- a big first import simply continues on the next run if it runs out of time.

create extension if not exists pg_cron;

select cron.unschedule('import-dealer-feeds') where exists (select 1 from cron.job where jobname = 'import-dealer-feeds');

select cron.schedule('import-dealer-feeds', '20 * * * *', $job$
  select net.http_post(
    url     := 'https://xhjybpostmfgwidqipgc.supabase.co/functions/v1/import-feed',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-import-secret', (select value from private.app_secrets where name = 'import_secret')),
    body    := '{}'::jsonb)
$job$);

-- Check (optional):   select jobname, schedule, active from cron.job;
-- Did it run?         select status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
-- Did the function answer?   select id, status_code, left(content, 300) from net._http_response order by id desc limit 5;
-- Stop the schedule:  select cron.unschedule('import-dealer-feeds');
