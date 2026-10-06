# Nearby: project spec

Read this file before every task. If a request conflicts with it, ask before proceeding.

## What we're building
A local classified ads website that feels as simple and familiar as Facebook Marketplace. Ads are shown by category. People find ads near them by choosing a city and a distance in miles. Everything should be easy to use and easy to follow.

## About the owner
I know HTML and classic ASP but haven't coded in over ten years. Explain each change in plain language, and compare it to classic ASP ideas when that helps (forms, sessions, SQL, includes). Keep the code simple and readable. Prefer plain, boring solutions over clever ones.

## Current state
`nearby-classifieds.html` is a working prototype in one HTML file with sample data held in memory. It already has:
- Category sidebar and ads grouped by category, plus a "View all" list
- Search, and sorting by newest, oldest, nearest, and price
- City search box (type-to-search, "City, ST"), a radius filter (5 to 100 miles or any), "nearby cities" shortcuts, and "Use my location"
- Listing detail pop-up with seller card, message box, and "Make an offer"
- Seller profile page with the seller's other listings
- Post-an-ad form with optional photo
- Save (heart) button and a Saved view
- Light and dark mode, mobile friendly

The visual design and flows in the prototype are the reference. Keep the look and behavior unless told otherwise.

## Target stack (keep it simple)
- **Front end:** plain HTML, CSS, and JavaScript. No framework for now.
- **Backend:** Supabase (Postgres database, login, photo storage). The page talks to Supabase directly with its JavaScript library.
- **Hosting:** Netlify or Vercel (static hosting).
- **Code storage:** Git and GitHub.
- Do not add frameworks, build tools, or libraries without asking first and explaining why.

## Data model (first version)
- `profiles`: id (matches the login user), display_name, created_at
- `categories`: id, name, icon
- `cities`: id, name, state, lat, lng
- `listings`: id, seller_id, category_id, city_id, title, description, price (0 means free), created_at, status ("active" or "sold"), is_demo
- `listing_photos`: id, listing_id, storage_path
- `favorites`: user_id, listing_id

Added later: `conversations`, `messages`, `offers`, `reviews`, `reports`.

Seed the categories and cities from the prototype's lists. Sample ads go in as demo rows (`is_demo = true`) so they can be deleted easily later.

## Security rules (not negotiable)
1. Only the public "anon" key may appear in the front-end code. The `service_role` key must never be in the page, in Git, or in any file that gets published.
2. Turn on row-level security on every table.
3. Anyone can read active listings. Only the signed-in owner can create, edit, or delete their own listings and photos.
4. Favorites are private to each user.
5. Escape all user-entered text before showing it on the page (the prototype's `esc()` function does this). Never build HTML from raw user text.
6. Photos: images only, with a maximum file size, stored in a Supabase Storage bucket with matching access rules.
7. Limit how many ads one account can post per day.

## Build phases
Work on one phase at a time, and within a phase one step at a time.

**Phase 1: Real data and accounts.** Done when: I can sign up, log in, and log out; the site loads categories, cities, and listings from the database; I can post an ad with a photo that persists after reload; I can edit and delete only my own ads; saved ads persist per account; and the site is live on a public web address.

**Phase 2: Core marketplace.** Done when: the city and radius filter runs in the database (a SQL function that finds listings within X miles of a city); sort and search work against real data; seller profiles use real accounts; a "mark as sold" button works; and the full city list comes from a public dataset (GeoNames), not hand-typed entries.

**Phase 3: Messaging and offers.** Conversations between buyer and seller, email alerts, and offers that the seller can accept, decline, or counter.

**Phase 4: Trust and safety.** Report buttons, a moderation queue, posting limits, spam checks, phone verification, scam warnings, and reviews after a sale.

**Phase 5: Launch.** Launch in one city, SEO-friendly city pages, analytics, and first revenue (paid featured listings).

## Working rules for the agent
- One small task at a time. Stop after each step and tell me how to test it.
- Before changing code, say what you plan to do in a few plain sentences.
- After each working step, make a Git commit with a clear message.
- Never delete or overwrite data or files without asking first.
- Never put secrets in code. Use a separate config file for the public Supabase URL and anon key.
- If something is unclear or a choice affects the design, ask me instead of guessing.
- Keep a short `NOTES.md` listing what's done, what's next, and any problems.

## Open decisions (owner fills in)
- Launch area: ______________________
- Site name and domain: ______________________
- First categories to keep or change (prototype has Vehicles, Property, Electronics, Furniture, Clothing, Sports, Jobs): ______________________
- How to make money first: ______________________
- Prohibited items list: ______________________
