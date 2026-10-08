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
