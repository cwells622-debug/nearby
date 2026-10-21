# Nearby: notes

## Done (Phase 1)
- Step 1: database tables, row-level security and seed data (`schema.sql`).
- Step 2: `config.js` (public Supabase URL and publishable key only) and `index.html` with sign up, log in, log out.
- Step 3: categories, cities and listings load from Supabase. 20 demo ads in `seed_demo.sql` (`is_demo = true`). Radius filter still runs in the browser.
- Step 4: post, edit and delete ads with photos (`step4_photos_and_limits.sql`: storage bucket, 5 MB and JPG/PNG/WebP limit, 10 ads per day, 5 photos per ad). Photos have EXIF/GPS data removed in the browser before upload and are resized to 1600px.
- Step 5: saved ads stored in the `favorites` table, private per user.
- Secret check before publishing: no `service_role` or secret key anywhere in the files or Git history. Only the public Supabase URL and publishable key are in `config.js`.

## SQL files, run in this order in the Supabase SQL Editor
1. `schema.sql`
2. `seed_demo.sql`
3. `step4_photos_and_limits.sql`
4. `seed_cities_us.sql` (7,513 US places with 5,000+ people, from GeoNames, CC BY 4.0)
5. `step7_vehicle_link.sql` (optional link on Vehicles ads)
6. `add_categories_2.sql` (ATV, Appliances, Campers, Real Estate, Medical, Motorcycles, Antiques, Lawn and Garden, Heavy Machinery)
7. `step8_admin.sql` (admin role; edit the email inside it to your own before running). Admin page: /admin.html
8. `step9_hide_categories.sql` (hides Jobs, Property, Real Estate, Furniture, Clothing, Appliances, Electronics; deletes their demo ads. Run BEFORE pushing the matching page update)
9. `hide_categories_2.sql` (hides Medical and Antiques)
10. `add_categories_3.sql` (Farm Equipment, Trailers, Tools)
11. `step11_video.sql` (video: uploaded clips up to 50 MB + YouTube/Vimeo links). Run BEFORE pushing the matching page update. Supabase free plan: 50 MB file cap and ~5 GB/month bandwidth, so watch usage.
12. `step12_cover_photo.sql` (cover photo choice + framing for the Marketplace-style grid). Run BEFORE pushing the matching page update.

## Step 6: publishing
- Code is on GitHub: https://github.com/cwells622-debug/nearby (branch `main`).
- Live site (Netlify): https://chadads.netlify.app/ . Netlify redeploys on every push to `main`.
- Only the `public/` folder is published (`index.html`, `config.js`), set in `netlify.toml`. SQL files, notes and the spec stay in GitHub only. Edit the site in `public/`.
- `nearby-classifieds.html` (the original prototype) stays in the repo root for reference and is not published.
- To do: in Supabase -> Authentication -> URL Configuration, set Site URL and Redirect URLs to the live address, so email confirmation links open the live site.
- To do: test sign up, posting with a photo and saving on the live site and on a phone.

## Next (Phase 2)
- City and radius filter in the database (SQL function), real GeoNames city list.
- Sort and search against the database, with paging (the page currently loads up to 500 ads).
- Seller profiles from real accounts, "mark as sold" button.

## Known problems and limits
- Photos are cleaned in the browser only. Someone calling Supabase directly could upload an uncleaned photo of their own. Server-side cleaning would need an Edge Function.
- Photos uploaded before the EXIF change may still contain location data.
- Message and offer buttons only show a confirmation. They are built in Phase 3.
- Demo sellers use made-up names and ratings. Delete demo ads with `delete from public.listings where is_demo;`.
- No bot protection (CAPTCHA) on sign-up yet (Phase 4).
- Site name, launch area and domain are still undecided (see PROJECT.md).

## Search engines
- Stage 1 done (titles, robots.txt, sitemap, structured data, About/Terms/Privacy, 404). Plan and to-do list: `SEO.md`.

## Video upload
- Video file upload is switched off in the form (October 2026). The YouTube/Vimeo link stays. Run `disable_video_upload.sql` to close it in the database too. To restore: run `step11_video.sql` again and remove `hidden` from `#vidUploadRow` in `public/index.html`.

## Categories
- `step13_autos_categories.sql`: 'Vehicles' renamed to 'Autos Cars' and 'Autos Trucks' added; the vehicle link box now works for both. The list of link-enabled categories lives in 3 places: `LINK_CATS` in `public/index.html`, the list in `public/admin.html`, and the trigger in `step13_autos_categories.sql`.

## Messaging
- `step14_messaging.sql`: conversations + messages (offers are messages with an amount), private to the two people, with spam limits (60 messages/hour, 20 new conversations/day). In-app only; the page checks for new messages every 30 s (10 s while the inbox is open). Email alerts need a sender address, so they are not built yet. Moderation/reports and admin access to threads are not built yet (Phase 4).

## Regions and category pages
- `step15_regions.sql` (run AFTER `seed_cities_us.sql`, and BEFORE pushing the matching page change): county codes and regions on cities, plus small NY towns and nearby VT/MA towns. Details and how to change a region: `SEO.md` (Stage 3).

## Photo speed
- Every photo has a small copy (~600 px JPEG) saved beside it: `abc.jpg` -> `abc_t.jpg` (`thumbPath()` in `public/index.html`, `public/admin.html` and `netlify/edge-lib/seo.js` must stay identical). Grids, strips and lists use it and fall back to the full photo if it is missing. New uploads make it automatically; deleting a photo or ad removes both.
- Photos uploaded before this need copies: run `step16_admin_photo_upload.sql`, then press 'Create small photo copies' on the admin page (safe to press again).
- Logo: `public/logo-sm.webp` (27 KB) is used in headers; `public/logo.webp` (254 KB) is only used for link previews.

## Getting sellers (Sell page and flyers)
- `/sell` (`public/sell.html`): why list, how it works, tips, FAQ. Its buttons go to `/?post=1`, which opens the Post form (or asks the visitor to log in first, then opens it).
- Print pieces: `/flyer` (one US Letter page) and `/flyer-sheet` (8 cut-out cards). Both are print-only pages (not indexed). Print with Margins: None and Background graphics: on.
- Both use `public/qr-sell.svg`, a QR code for `https://chadads.com/sell` (error correction Q, checked with a decoder). If the web address ever changes, the QR code must be regenerated (it is just a picture of the address).
- There is no analytics yet, so scans and visits can't be counted. Add privacy-friendly analytics (e.g. Plausible) before a big print run.

## Analytics (Cloudflare Web Analytics)
- `public/analytics.js` adds Cloudflare's counter. It does NOTHING until the TOKEN line in that file is filled in (get it from Cloudflare dashboard > Web Analytics > your site > JavaScript snippet; it is public, not a secret), then push.
- Only chadads.com / www.chadads.com are counted. Not counted: localhost, the old netlify.app address, browsers that send Do Not Track, and the owner's browser (visit `/admin.html` or `/?noanalytics=1` once per browser; `/?noanalytics=0` undoes it).
- Cloudflare Web Analytics has no custom events. Printed pieces are told apart by their own addresses: flyer QR -> `/s/flyer`, card QR -> `/s/card` (both show the Sell page; files `public/qr-flyer.svg` and `public/qr-card.svg`). Look for those paths in the dashboard. `qr-sell.svg` (`/sell`) is the older, untagged code.
- The Privacy page mentions the counting. If the provider changes, update it.

## All US towns (city search)
- Cities: `seed_cities_us.sql` (places of 5,000+), `step15_regions.sql` (small NY/VT/MA towns), then `step17_cities_1..5.sql` (about 26,000 more places from the US Census Gazetteer 2024: every incorporated place and census-designated place, plus the legal towns of NY, VT and MA). Same-name places far apart are named like `Chester (Warren Co.), NY`. Tiny hamlets that are not Census places (e.g. Riparius) are not in the list; sellers pick their town instead.
- `step17_city_search.sql` (run AFTER the five city files): `search_cities()` and `nearest_city()` functions, and the regions for the new places. The county of each new place is a guess from the nearest town centre (about 97% right); fix a wrong one with an `update ... set county_fips` and re-run section 3 of that file.
- The site no longer loads every city on each visit. Ads bring their own city along (`cities(...)` in the listings query); the Post form, the browse city box and the admin edit box search as you type; "Use my location" calls `nearest_city()`. RUN THE SQL BEFORE PUSHING the matching page change, or cities that have no ads yet can't be picked.

## Call for price
- `step18_price_on_request.sql` adds `listings.price_on_request`. When ticked in the Post form (or admin edit box) the ad shows "Call for price" everywhere (cards, pop-up, share text, message header, search-engine pages) and the price is stored as 0. Those ads sort last in the price sorts, get no "Make an offer" button, and have no price in the Google structured data. The words live in `pt()` in `public/index.html`, `priceText()` in `netlify/edge-lib/seo.js` and the admin table cell.
- RUN THE SQL BEFORE PUSHING: the pages ask the database for that column, so without it the site shows "Couldn't load listings".

## Instagram post maker
- In the ad pop-up's share row, the Instagram icon opens a dialog (`#dIg` in `public/index.html`, code `openIg()` and friends just above the gallery code). It draws 1080x1350 (4:5) pictures on canvas: picture 1 = cover photo + price with the logo to its right + title + town (no web address on the pictures; it is in the caption); pictures 2+ = the whole photo on a dark backdrop with a ChadAds strip (logo and price). Up to 10 photos (ads allow 5). It also writes a caption (title, price, town, 300 characters of the description, link, hashtags from category/town/region).
- Instagram has no "post from a website" option. Buttons: Share (phones that can share files: pick Instagram), Save pictures (downloads the files), Copy caption. The photos must come from Supabase storage with CORS on (it is: `Access-Control-Allow-Origin: *`); if that ever changes the canvas can't be exported.
- Nothing is stored or uploaded; everything happens in the visitor's browser.

## Auto categories (renamed)
- `step19_auto_categories.sql`: 'Autos Cars' -> 'Auto Cars', 'Autos Trucks' -> 'Auto Trucks', new 'Auto SUVs'. The link box list is now in 4 places: `LINK_CATS` in `public/index.html`, the list in `public/admin.html`, the trigger in `step19_auto_categories.sql` (replaces the one in step13), and nothing else. Category page addresses follow the name (`/for-sale/auto-cars`, `/auto-trucks`, `/auto-suvs`); `netlify/edge-functions/browse.js` redirects the old `autos-cars` / `autos-trucks` addresses (301). RUN THE SQL, THEN PUSH AT ONCE: until the push, the site's link box and page labels still use the old names.

## Email alerts (new message or offer)
- How it flows: a message is saved -> the trigger `message_notify` (in `step20_email_alerts.sql`) decides who to tell and sends the email straight from the database through Resend (`net.http_post`) from `notifications@chadads.com`. The recipient's address is read inside the database only. The email shows a preview and a View message button (`/?messages=<conversation id>`, which logs them in if needed and opens the thread).
- Limits: one email per person per thread per 15 minutes; none if the person switched alerts off ("Email me about new messages" switch at the top of the Messages screen, or the Unsubscribe link in the email, `public/unsubscribe.html`). Alerts can never stop a message from being saved (the trigger swallows errors).
- The Resend key lives ONLY in the database table `private.app_secrets` (name `resend_api_key`; insert it in the SQL Editor, see the bottom of the SQL file). Never in GitHub. Delete that row to switch alerts off everywhere. (We first tried a Netlify function with Netlify environment variables, but the function never saw them, so it was removed.)
- Resend setup: free account, domain chadads.com verified (DNS records added in Netlify DNS), an API key. Free plan: 3,000 emails/month, 100/day. If an email never arrives: Resend dashboard > Logs; and in Supabase `select id, status_code, content from net._http_response order by id desc limit 5;`.
- Not built: a daily summary, SMS, and replying to the email (it says to reply on ChadAds).

## Dealer feed import (not started, waiting for a sample)
- Idea: import a dealer's inventory (via carsforsale.com or the dealer directly) as ads. Do NOT scrape carsforsale.com; get permission and a feed from the dealer or carsforsale.com.
- Wanted: UTF-8 CSV, one row per vehicle, FULL inventory each time (so sold cars disappear), delivered as a private HTTPS link (or SFTP), daily. Columns: VIN or stock number, year, make, model, trim, price, mileage, body type, description, photo URLs (separated by `|`), dealer name, city, state.
- Plan once a sample file arrives: map columns, add `source` + `external_id` to listings, a scheduled importer that adds/updates/removes by VIN, copy up to 5 photos into storage (with thumbnails), "Dealer" label, per-dealer ad cap and a pause switch. The feed link is a secret: store it in `private.app_secrets`, never in GitHub.

## Report an ad
- `step21_reports.sql` (run after step8_admin.sql and step20_email_alerts.sql): table `reports` (reasons: scam, prohibited, spam, wrong, misleading, offensive, sold, other), one report per person per ad, 10 per person per day, not on your own ad. RUN THE SQL BEFORE PUSHING the page change (the site sends reports to that table).
- On the site: logged-in members see "Report this ad" at the bottom of an ad pop-up (`#dRep`, `openReport()` in `public/index.html`). Logged-out visitors are asked to log in first. The seller is never told who reported.
- Admin page (`public/admin.html`): a "Reports" tab with a count. One card per ad with every report on it. Buttons: Find in Ads (to edit or delete the ad with the existing buttons), Mark handled, Dismiss (these close every open report on that ad). Choose "Handled / Dismissed / Everything" to see old ones.
- Each new report emails hello@chadads.com (or the address in `private.app_secrets` name `admin_email`) through Resend, like message alerts. No Resend key = reports still work, just no email.
- Not built yet: auto-hiding an ad after several reports, blocking a user from messaging you, reporting a message or a user.

## Block a member (messaging)
- `step22_block_users.sql` (run after step14_messaging.sql; RUN IT BEFORE PUSHING the page change): table `blocks` (blocker, blocked; only the blocker can see or change their own), `block_state()` function, and updated `conversation_before_insert` / `message_before_insert` triggers that refuse new conversations, messages and offers while a block exists in EITHER direction. The blocked person is not told: they see "This member is not accepting messages." The blocker sees "You have blocked this member. Unblock them to send messages."
- On the site: in the Messages screen, each conversation has a Block / Unblock button at the top right (`toggleBlock()` in `public/index.html`). A blocked conversation shows a "Blocked" tag, its composer is disabled, and it no longer counts as unread. The "Message" button on an ad also tells you if you blocked the seller. Old messages stay readable.
- Not built: blocking from an ad page or profile without a conversation, an admin list of blocks, auto-blocking after reports.

## Town pages (/in/north-creek-ny)
- Any town in the cities table has a page at `/in/<town>-<state>` (`cityPath()` in `netlify/edge-lib/seo.js`, built by `netlify/edge-functions/browse.js`; `findCity()` looks the town up in the database). No SQL needed. Unknown towns get the normal 404.
- A town WITH ads shows its own ads and is offered to Google (`INDEX_MIN.city`) and listed in the sitemap. A town WITHOUT ads shows the newest ads from about 25 miles around it ("Classifieds near ..."), is marked noindex, and is not in the sitemap (so hundreds of empty towns don't look like duplicate pages).
- The page app also opens with that town and 25 miles chosen (`LAND.city` in `public/index.html`). Ad pages link to their town page. Tiny catch: towns whose first letters are not plain a-z (accents) may not resolve.
- Not built: town + category pages (`/for-sale/auto-trucks/saratoga-springs-ny`) and a page listing all towns.

## Print a For Sale sign (QR code)
- A printer icon in the ad pop-up's share row opens `/sign?ad=ID` (`public/sign.html`, new tab): a US Letter "FOR SALE" sign with the ad's first photo, price, title, town, a one-line "go to chadads.com for more photos and details" note (no description), a QR code to `https://chadads.com/ad/ID-slug` and the short address `chadads.com/ad/ID`, plus the logo. The page fetches the ad itself, so it works for any active ad (and the owner's own sold ads). Print with Margins: None and Background graphics: on (the page says so). Not indexed (`robots.txt`, `noindex`).
- The QR code is drawn in the browser by `public/qrcode.js` = the open-source "qrcode-generator" 1.4.4 by Kazuhiko Arase (MIT license; the license text is in the file header, keep it). It only loads on the sign page. The QR always points at chadads.com, even if the page is opened somewhere else. If the slug rule changes (`slugify`), `sign.html` has a copy that must match.
- Layout: photo 3.6in tall, the title is clamped to 2 lines; the sizes were checked so a long title still fits one page.
- Not built: other sizes (half-page, 4x6), choosing a different photo, tear-off phone tabs.

## Dealer feed import (carsforsale.com feed, many dealers; first dealer Marchese Ford, New Lebanon NY)
- One FEED (carsforsale.com) holds the cars of many dealers; each row has a DealerID. Dealers are set up one by one; cars from DealerIDs we have not set up are ignored and listed in the admin preview ("Dealers in the file that are not set up yet").
- Sample feed layout (CSV, every field quoted): DealerID, NEWUSED, VIN, StockNumber, Make, Model, ModelYear, Trim, BodyStyle (only 4DR/5DR/CONV), Mileage, EngineDescription, Cylinders, FuelType, Transmission, Price, ExteriorColor, InteriorColor, Options (comma list), Description (dealer text + boilerplate), Images (comma-separated links, 13-21 per car). No dealer name/town in the file (we store them per DealerID). The photo links in the 2009 sample are dead (404), so a real feed must have live links.
- Pieces: `step23_dealer_feed.sql` (is_dealer flag, `listings.external_id` = VIN, `feed_hash`, private tables `private.feed_sources` (holds the SECRET feed link) and `private.feed_dealers` (DealerID -> account, name, town), dealers exempt from the 10-ads/day limit, the one-line `private.add_feed_dealer(...)`, helper functions only the importer can call); `supabase/functions/import-feed/index.ts` (the importer, a Supabase Edge Function: parse CSV, split by DealerID, map, add/update/hide by VIN, copies up to 5 photos per car into storage, never wipes a dealer's ads if their part of the file is empty or under half size, stops after ~100 s and continues next run); `step24_feed_schedule.sql` (pg_cron, hourly); admin page tab "Dealer feeds" (Preview = dry run, Import now).
- ADDING A DEALER LATER: they sign up on chadads.com, then in the SQL Editor run  select private.add_feed_dealer('carsforsale.com', '<DealerID>', '<their login email>', '<Dealer name>', '<Town>', '<ST>');  The next import picks them up. Pause one: update private.feed_dealers set active = false where dealer_code = '...';
- Tested with fakes in a browser (grouping by DealerID, unknown dealers, dry run writes nothing, create/unchanged/update/hide, 5 photos max, empty-dealer safety, wrong secret refused). NOT yet tested against the real Supabase or the real feed.
- The top half of index.ts is pure mapping code (titles tidied, category by model name, boilerplate dropped, change detection). To change categories or tidy rules edit `categoryFor`, `niceCase`, `BOILERPLATE` there, then re-deploy the function (paste the file again in the Supabase dashboard).
- Deploy: Supabase dashboard > Edge Functions > Deploy a new function > name `import-feed` > paste index.ts > Deploy, then in its settings turn OFF "Verify JWT" (the function checks the caller itself: the `import_secret` header or an admin login). No Netlify variables are used.
- Ads from a dealer show a "Dealer" tag next to the seller name in the ad pop-up. Cars that leave the feed are set to status "sold" (hidden). RUN step23 BEFORE pushing the page change (the site now asks for `profiles.is_dealer`).
- Not built: choosing categories by VIN lookup, a per-dealer boilerplate list in the database, SFTP feeds, thumbnails for imported photos (the site falls back to the full photo), a "Dealer" badge on cards, an admin screen for adding dealers (it is one SQL line for now).

## Sign-in emails (Supabase Auth)
- Sender name "ChadAds" needs custom SMTP in the Supabase dashboard (Authentication > Emails > SMTP Settings): host smtp.resend.com, port 465, user `resend`, password = a Resend API key made for this (never in GitHub), sender `notifications@chadads.com`, sender name `ChadAds`. This also lifts Supabase's very low built-in email limit.
- Branded email bodies are in `supabase/email-templates/` (confirm-signup, invite-user, reset-password). Paste each into Authentication > Emails > Templates (the subject is written at the top of each file as a comment). They use `{{ .ConfirmationURL }}`, which Supabase fills in.
- The importer must answer the browser's OPTIONS "preflight" with CORS headers (`CORS` in index.ts), otherwise the admin page's Preview / Import now buttons say "Failed to fetch". Whenever index.ts changes it must be pasted into the Supabase dashboard again (Edge Functions > import-feed > edit > Deploy).
- REAL carsforsale.com export format (from `multi dealer sample export.txt`, 57 cars, 2 dealers): same 20 columns but spelled `NewUsed` and `images` (so column names are matched ignoring capitals), photos on `cdn05.carsforsale.com` at 1280x960 (6-100 per car; we copy 5), `BodyStyle` is a real word (Coupe, Convertible, Pickup Truck, SUV, Sedan, Motorcycles & Scooters), most classic cars have NO VIN (we use `STK-<stock number>` as the car's ID; a real 17-character VIN is used when present), descriptions contain HTML (`<br />`; converted to text) and the dealer's phone number, some prices are 0 (shown as "Call for price"), stock numbers are occasionally duplicated inside a dealer (the later row is skipped and counted).
- Dealers seen: DealerID 1035978 = Caruso Classics (Massachusetts classic and muscle cars, 54 cars); DealerID 1017907 = 3 Ford Explorer Police Interceptors, name and town unknown. Tested the whole importer with fakes on this file: 52 ads created, 260 photos (5 per car), 2 duplicates skipped, unknown dealer reported, second run unchanged.
- BodyStyle words that map to other categories: Motorcycle/Scooter -> Motorcycles, Snowmobile, ATV/UTV, Boat/Pontoon, Motorhome/Camper/Travel trailer, Trailer. Edit `categoryFor` in index.ts to change.
