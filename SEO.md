# ChadAds: search engine plan

Written October 2026. Keep this file up to date as pages are added.

## The key idea
ChadAds is one web page that draws its ads with JavaScript. Search engines (and Facebook, WhatsApp, etc. for link previews)
see only the page itself, not each ad. So the work is in two stages:

1. **Basics (done):** make the one page and the plain pages easy for search engines to understand.
2. **Real pages for ads, cities and categories (next):** give each its own address with its own title, text and photo.
   This is where most classifieds traffic comes from.

## Stage 1: what exists now
| Item | Where | Notes |
|---|---|---|
| Title and description | `public/index.html` head | About 60 and 150 characters. Names the launch area (Capital District, Albany, Saratoga, Troy, Adirondacks, Hudson Valley, Upstate NY). |
| Canonical address | `public/index.html` head | `?ad=...` and `?q=...` links all count as the home page. **Change this when real ad pages exist.** |
| Social/link-preview tags | `public/index.html` head | Same for every share until ad pages exist. |
| Structured data (JSON-LD) | `public/index.html` head | Organization + WebSite with a search box (`/?q=...`). |
| `robots.txt` | `public/robots.txt` | Blocks `/admin.html`. Points at the sitemap. |
| `sitemap.xml` | built live by `netlify/edge-functions/sitemap.js` | `public/sitemap.xml` is only a fallback. |
| About, Terms, Privacy pages | `public/*.html`, style in `public/page.css` | Clean addresses set in `netlify.toml`. Drafts: have them reviewed before launch. |
| Footer links | bottom of the home page | Gives search engines links to the plain pages. |
| 404 page | `public/404.html` | Netlify shows it automatically. |
| Safety/caching headers | `public/_headers` | |
| Photo alt text, lazy loading | `public/index.html` | Alt text = the ad title. |

## Stage 2: real pages for ads (built, October 2026)
**Decision recorded:** the pages are built by **Netlify Edge Functions**, not Supabase Edge Functions.
Supabase rewrites any HTML an Edge Function returns to plain text on its normal address (its docs: "GET requests that return text/html
will be rewritten to text/plain"; HTML needs a paid custom domain), so it cannot serve web pages for us.
Netlify's cost for this is small: web requests are about 2 credits per 10,000, bandwidth 20 credits/GB, and function compute 10 credits/GB-hour
(deploys, at 15 credits each, are the expensive thing, so batch pushes).

How it works:
- `/ad/38-2017-jeep-rubicon` is handled by `netlify/edge-functions/ad.js`. It asks the database for ad 38 (public key, so only active ads are
  visible), fetches the normal home page, and fills in that ad's own title, description, canonical address, preview photo, `Product`/`Offer`
  structured data and readable text. The app then starts as usual and opens the ad pop-up. Search engines and link previews see the full ad.
- Wrong or old words in the address get a 301 redirect to the right address. Missing, sold, deleted, or hidden-category ads return the branded 404 with `noindex`.
- `/sitemap.xml` is built by `netlify/edge-functions/sitemap.js` from the live ads (up to 10,000; split into several sitemaps beyond that).
  `public/sitemap.xml` is only a fallback if the function ever fails to deploy.
- Shared logic (address words, escaping, page and sitemap builders) is in `netlify/edge-lib/seo.js`.
  `slugify()` exists twice (there and in `public/index.html`) and MUST stay identical.
- The CDN keeps each generated page for 5 minutes (sitemap 1 hour), so crawler bursts cost almost nothing.
- Old `?ad=26` links still open the ad in the app. Share links now use the `/ad/...` address, so previews show that ad's own photo.

Things to remember:
- The public database key is copied into `netlify/edge-lib/seo.js` (same value as `public/config.js`). If that key is ever rotated, change both.
- When the home page changes its head tags (title, description, canonical, og: and twitter: tags), keep the exact tag formats,
  because `buildAdPage()` finds and replaces them by pattern. Test by loading `/ad/<id>-<anything>` after a deploy.
- The home page `canonical` stays `https://chadads.com/`. Ad pages set their own.

## Stage 3: next
1. **City and category pages**, e.g. `/vehicles/saratoga-springs-ny`, `/vehicles/capital-district`: same pattern (a new edge function), with a list of the ads, unique text, and `ItemList` data. Add them to the sitemap.
2. **Speed:** smaller grid photos (600 px copies), a smaller logo file (254 KB now).
3. **Analytics** that respects privacy (for example Plausible).
4. **Content and links:** local Facebook groups, local directories, a Google Business Profile if there is a physical presence.
## One-time tasks for the site owner
- [ ] Google Search Console: add `https://chadads.com` as a property, verify it (DNS record at GoDaddy, or an HTML file we add), submit `https://chadads.com/sitemap.xml`.
- [ ] Bing Webmaster Tools: same (it can import from Search Console).
- [ ] Add a contact email to the About, Terms and Privacy pages (and set up the mailbox).
- [ ] Have the Terms and Privacy pages reviewed. The prohibited-items list in PROJECT.md is still undecided.

## Rules to keep as the site grows
- Every indexable page needs a **unique title and description** and one **h1**.
- One address per piece of content. Use `canonical` to point duplicates (filters, sort orders, `?ad=`) at the main one.
- Never index the admin page, sign-in pages, or anything private.
- When a page is added, add it to the sitemap (or to whatever generates it).
- Check results in Search Console monthly (coverage errors, which searches bring clicks).
