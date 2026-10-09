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
| Title and description | `public/index.html` head | About 60 and 130 characters. Add the launch city once chosen. |
| Canonical address | `public/index.html` head | `?ad=...` and `?q=...` links all count as the home page. **Change this when real ad pages exist.** |
| Social/link-preview tags | `public/index.html` head | Same for every share until ad pages exist. |
| Structured data (JSON-LD) | `public/index.html` head | Organization + WebSite with a search box (`/?q=...`). |
| `robots.txt` | `public/robots.txt` | Blocks `/admin.html`. Points at the sitemap. |
| `sitemap.xml` | `public/sitemap.xml` | Hand-written (home, About, Terms, Privacy). **Must become automatic.** |
| About, Terms, Privacy pages | `public/*.html`, style in `public/page.css` | Clean addresses set in `netlify.toml`. Drafts: have them reviewed before launch. |
| Footer links | bottom of the home page | Gives search engines links to the plain pages. |
| 404 page | `public/404.html` | Netlify shows it automatically. |
| Safety/caching headers | `public/_headers` | |
| Photo alt text, lazy loading | `public/index.html` | Alt text = the ad title. |

## Stage 2: the growth plan (needs a decision first)
Why a decision: it adds a server-side piece (PROJECT.md: ask before adding new technology), and some choices cost money or Netlify credits.

1. **A real page for every ad**, e.g. `chadads.com/ad/38-2017-jeep-rubicon`, containing the title, price, city, description, photo
   and `Product`/`Offer` structured data (this is what lets Google show price and photo in results).
   - Built on demand by a small function. Candidates: Supabase Edge Function (large free allowance, close to the data),
     Netlify function (costs credits per visit; bots visit a lot), or a different host.
   - The visible site stays the same: the page can hand over to the normal app once loaded.
   - Sold or deleted ads: return "gone" (410) or `noindex`, and drop them from the sitemap.
   - Then change the home page canonical and make `?ad=` links point to the real address.
2. **Automatic sitemap** listing every active ad (and city/category page), refreshed as ads change.
3. **City and category pages**, e.g. `/vehicles/saratoga-springs-ny` ("used vehicles for sale in Saratoga Springs").
   The 7,500 US cities already in the database make this easy to generate.
4. **Speed:** smaller grid photos (600 px copies), a smaller logo file (254 KB now). Google scores speed on phones.
5. **Analytics** that respects privacy (for example Plausible), so we can see what brings people in.
6. **Content and links:** local Facebook groups, a Google Business Profile if there is a physical presence, local directories, press.

## One-time tasks for the site owner
- [ ] Google Search Console: add `https://chadads.com` as a property, verify it (DNS record at GoDaddy, or an HTML file we add), submit `https://chadads.com/sitemap.xml`.
- [ ] Bing Webmaster Tools: same (it can import from Search Console).
- [ ] Choose the launch city/region. It belongs in titles and descriptions.
- [ ] Add a contact email to the About, Terms and Privacy pages (and set up the mailbox).
- [ ] Have the Terms and Privacy pages reviewed. The prohibited-items list in PROJECT.md is still undecided.

## Rules to keep as the site grows
- Every indexable page needs a **unique title and description** and one **h1**.
- One address per piece of content. Use `canonical` to point duplicates (filters, sort orders, `?ad=`) at the main one.
- Never index the admin page, sign-in pages, or anything private.
- When a page is added, add it to the sitemap (or to whatever generates it).
- Check results in Search Console monthly (coverage errors, which searches bring clicks).
