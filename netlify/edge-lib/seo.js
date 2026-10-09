// Shared helpers for the search-engine pages (see SEO.md).
// Used by netlify/edge-functions/ad.js and sitemap.js. Plain functions with no outside libraries,
// so they can also be tested by pasting them into any browser console.

export const SITE = "https://chadads.com";
// These two are the PUBLIC database address and key, the same ones that are in public/config.js.
// Row-level security in the database decides what they can read. Never put the secret key here.
export const SB_URL = "https://xhjybpostmfgwidqipgc.supabase.co";
export const SB_KEY = "sb_publishable_uuz1NgftKiBRGtME6enOzg_nELwZIpz";

// What we ask the database for about one ad.
export const AD_SELECT =
  "id,title,description,price,created_at,video_link," +
  "categories(name,active),cities(name,state,regions)," +
  "listing_photos(id,storage_path,position),profiles!seller_id(display_name)";

// Escape text before putting it into HTML (so nobody can inject markup).
export const esc = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

// "2017 Jeep Rubicon!" -> "2017-jeep-rubicon". MUST stay identical to slugify() in public/index.html.
export const slugify = (t) =>
  String(t || "").toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60).replace(/-+$/, "") || "ad";

export const adPath = (id, title) => `/ad/${id}-${slugify(title)}`;
export const money = (p) => (Number(p) === 0 ? "Free" : "$" + Number(p).toLocaleString("en-US"));
const clip = (s, n) => {
  s = String(s ?? "").replace(/\s+/g, " ").trim();
  return s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s;
};
const photoUrl = (p) => `${SB_URL}/storage/v1/object/public/listing-photos/${p}`;
// The small copy saved next to each photo ("abc.jpg" -> "abc_t.jpg"). MUST match thumbPath() in public/index.html.
export const thumbPath = (p) => p.replace(/\.[A-Za-z0-9]+$/, "_t.jpg");
export const sortedPhotos = (ad) =>
  [...(ad.listing_photos || [])].sort((a, b) => (a.position - b.position) || (a.id - b.id));

// Makes JSON safe to sit inside a <script> tag.
const safeJson = (o) => JSON.stringify(o).replace(/</g, "\\u003c").replace(new RegExp("[" + String.fromCharCode(0x2028, 0x2029) + "]", "g"), "");

// Replaces one meta tag's content (the tag is found by its name= or property= label).
function setMeta(html, attr, label, content) {
  const re = new RegExp(`<meta ${attr}="${label}" content="[^"]*">`);
  return html.replace(re, () => `<meta ${attr}="${label}" content="${esc(content)}">`);
}

// Links from an ad to its category and region pages (good for visitors and for search engines finding those pages).
function relatedLinks(ad) {
  const cat = ad.categories && ad.categories.name;
  if (!cat) return "";
  const regs = (ad.cities && ad.cities.regions) || [];
  const r = REGION_ORDER.find((x) => regs.includes(x));
  const out = [`<a href="${browsePath(cat, null)}">More ${esc(catLabel(cat).toLowerCase())} for sale</a>`];
  if (r) {
    out.push(`<a href="${browsePath(cat, r)}">${esc(catLabel(cat))} for sale in ${esc(REGIONS[r].short)}</a>`);
    out.push(`<a href="${browsePath(null, r)}">Classifieds in ${esc(REGIONS[r].short)}</a>`);
  }
  return `<nav aria-label="Related pages"><p>${out.join(" · ")}</p></nav>`;
}

// Takes the normal home page (the "shell") and returns the same page with this ad's own title,
// description, preview picture, structured data and readable text filled in. The app still starts
// as usual and opens this ad's pop-up.
// NOTE: every .replace() below uses a function for the new text, because text with a "$" in it
// (like "$5,000") would otherwise be misread as a special code.
export function buildAdPage(shell, ad) {
  const photos = sortedPhotos(ad).map((p) => photoUrl(p.storage_path));
  const city = ad.cities ? `${ad.cities.name}, ${ad.cities.state}` : "";
  const cat = ad.categories ? ad.categories.name : "";
  const seller = ad.profiles && ad.profiles.display_name ? ad.profiles.display_name : "a local seller";
  const url = SITE + adPath(ad.id, ad.title);
  const pageTitle = `${clip(ad.title, 52)} – ${money(ad.price)}${city ? " in " + city : ""} | ChadAds`;
  const desc = clip(`${money(ad.price)}${city ? " · " + city : ""}. ${ad.description}`, 155);
  const image = photos[0] || SITE + "/logo.webp";

  let h = shell;
  h = h.replace(/<title>[\s\S]*?<\/title>/, () => `<title>${esc(pageTitle)}</title>`);
  h = h.replace(/<meta name="description" content="[^"]*">/, () => `<meta name="description" content="${esc(desc)}">`);
  h = h.replace(/<link rel="canonical" href="[^"]*">/, () => `<link rel="canonical" href="${esc(url)}">`);
  h = setMeta(h, "property", "og:url", url);
  h = setMeta(h, "property", "og:title", pageTitle);
  h = setMeta(h, "property", "og:description", desc);
  h = setMeta(h, "property", "og:image", image);
  h = setMeta(h, "property", "og:image:alt", `${ad.title} for sale`);
  h = setMeta(h, "name", "twitter:title", pageTitle);
  h = setMeta(h, "name", "twitter:description", desc);
  h = setMeta(h, "name", "twitter:image", image);
  // The logo's size tags don't describe an ad photo, so drop them when we use one.
  if (photos[0]) h = h.replace(/<meta property="og:image:(width|height)" content="[^"]*">\n?/g, () => "");

  const ld = {
    "@context": "https://schema.org",
    "@type": "Product",
    name: ad.title,
    description: clip(ad.description, 500),
    url,
    ...(photos.length ? { image: photos.slice(0, 5) } : {}),
    ...(cat ? { category: cat } : {}),
    offers: {
      "@type": "Offer",
      url,
      price: String(ad.price),
      priceCurrency: "USD",
      availability: "https://schema.org/InStock",
      ...(city ? { areaServed: city } : {}),
    },
  };
  const headExtra =
    `<meta name="robots" content="index,follow,max-image-preview:large">\n` +
    `<script type="application/ld+json">${safeJson(ld)}</script>\n`;
  h = h.replace("</head>", () => headExtra + "</head>");

  const imgs = photos.slice(0, 5)
    .map((u, i) => `<img src="${esc(u)}" alt="${esc(ad.title)} (photo ${i + 1})" ${i ? 'loading="lazy"' : ""} style="max-width:100%;height:auto;border-radius:12px;margin:6px 0">`)
    .join("\n");
  const article =
    `<article class="seo-ad"><h1>${esc(ad.title)}</h1>` +
    `<p><strong>${esc(money(ad.price))}</strong>${city ? " · " + esc(city) : ""}${cat ? " · " + esc(cat) : ""}</p>` +
    `${imgs}<p style="white-space:pre-line">${esc(ad.description)}</p>` +
    `<p>Listed by ${esc(seller)} on ChadAds. <a href="/">Browse more local classifieds</a>.</p>${relatedLinks(ad)}</article>`;
  h = h.replace(/<main id="main">[\s\S]*?<\/main>/, () => `<main id="main">${article}</main>`);
  return h;
}

// ======================================================================
// Category and region pages:  /for-sale/autos-trucks   /in/capital-district   /for-sale/autos-trucks/capital-district
// ======================================================================
// Regions are defined in the database (cities.regions, set by step15_regions.sql). This list only adds the words
// shown to people. The keys here MUST match the region names used in step15_regions.sql.
export const REGIONS = {
  "capital-district": { name: "Capital District", short: "the Capital District",
    blurb: "Albany, Troy, Schenectady, Saratoga Springs and the towns around them, plus nearby southern Vermont and the Berkshires." },
  "adirondacks": { name: "Adirondacks", short: "the Adirondacks",
    blurb: "Glens Falls, Queensbury, Lake Placid, Saranac Lake, Plattsburgh and the Adirondack towns." },
  "hudson-valley": { name: "Hudson Valley", short: "the Hudson Valley",
    blurb: "Poughkeepsie, Kingston, Newburgh, Middletown, Hudson and the towns along the river." },
  "upstate-new-york": { name: "Upstate New York", short: "Upstate New York",
    blurb: "all of New York north of the New York City area, from Buffalo and Rochester to the Capital District and the Adirondacks." },
};
export const REGION_ORDER = ["capital-district", "adirondacks", "hudson-valley", "upstate-new-york"];   // most specific first

// Short words for page titles and a sentence about each category. A category not listed here still works (it uses its own name).
export const CATEGORY_INFO = {
  "ATV": { label: "ATVs", blurb: "Four-wheelers, side-by-sides and utility ATVs from local owners." },
  "Autos Cars": { label: "Cars", blurb: "Used and late-model cars, SUVs and wagons from local sellers." },
  "Autos Trucks": { label: "Trucks", blurb: "Pickups, 4x4s and work trucks from local sellers." },
  "Campers": { label: "Campers", blurb: "Travel trailers, pop-ups, truck campers and motorhomes for sale locally." },
  "Farm Equipment": { label: "Farm Equipment", blurb: "Tractors, implements and farm machinery from local farms and dealers." },
  "Heavy Machinery": { label: "Heavy Machinery", blurb: "Excavators, loaders, dozers and other construction equipment." },
  "Lawn and Garden": { label: "Lawn & Garden Equipment", blurb: "Mowers, tractors, tillers, chainsaws and outdoor power equipment." },
  "Motorcycles": { label: "Motorcycles", blurb: "Street, cruiser, dirt and touring motorcycles from local riders." },
  "Sports": { label: "Sports & Outdoor Gear", blurb: "Bikes, boats, fitness and outdoor gear from local sellers." },
  "Tools": { label: "Tools", blurb: "Hand tools, power tools and shop equipment for sale locally." },
  "Trailers": { label: "Trailers", blurb: "Utility, car-hauler, dump, enclosed and equipment trailers." },
};
export const catLabel = (name) => (CATEGORY_INFO[name] && CATEGORY_INFO[name].label) || name;
const catBlurb = (name) => (CATEGORY_INFO[name] && CATEGORY_INFO[name].blurb) || `Local ${name.toLowerCase()} listings.`;

// How many ads a page needs before search engines are told to list it. Small or empty pages stay out of Google
// (they still work for visitors). Raise these numbers as the site grows.
export const INDEX_MIN = { category: 1, region: 1, combo: 3 };
export const isIndexable = (catName, region, total) => total >= (catName && region ? INDEX_MIN.combo : catName ? INDEX_MIN.category : INDEX_MIN.region);

// Page addresses
export const browsePath = (catName, region) =>
  catName ? `/for-sale/${slugify(catName)}${region ? "/" + region : ""}` : `/in/${region}`;
// "/for-sale/autos-trucks/capital-district" -> { cat: "autos-trucks", region: "capital-district" }; null if it is not one of ours.
export function parseBrowsePath(pathname) {
  const p = pathname.replace(/\/+$/, "").split("/").filter(Boolean);
  if (p[0] === "in" && p.length === 2 && REGIONS[p[1]]) return { cat: null, region: p[1] };
  if (p[0] === "for-sale" && p.length === 2) return { cat: p[1], region: null };
  if (p[0] === "for-sale" && p.length === 3 && REGIONS[p[2]]) return { cat: p[1], region: p[2] };
  return null;
}

// Fills the home page shell with a list page: its own title, description, preview, structured data, a readable list of
// ads, and a small "landing" note the app uses to show the same filter on screen.
export function buildListPage(shell, { catName, region, ads, total, cats }) {
  const R = region ? REGIONS[region] : null;
  const label = catName ? catLabel(catName) : null;
  const path = browsePath(catName, region);
  // "Trucks in Upstate New York" shows the same ads as "Trucks" (the whole site is Upstate New York), so it points at the plain category page.
  const url = SITE + (catName && region === "upstate-new-york" ? browsePath(catName, null) : path);
  const where = R ? R.short : "the Capital Region and Upstate New York";
  const h1 = catName ? `${label} for sale in ${where}` : `Local classifieds in ${where}`;
  const pageTitle = catName
    ? `${label} for Sale in ${R ? R.short : "the Capital Region & Upstate NY"} | ChadAds`
    : `Local Classifieds in ${R.short} | ChadAds`;
  const intro = catName
    ? `${catBlurb(catName)} ${R ? "Showing ads from " + R.short + ": " + R.blurb : "Browse sellers across the Capital District, the Adirondacks, the Hudson Valley and the rest of Upstate New York."}`
    : `Browse local ads in ${R.short}: ${R.blurb}`;
  const desc = clip(`${total ? total + " ad" + (total === 1 ? "" : "s") + ". " : ""}${intro} Free to list on ChadAds.`, 155);
  const indexable = isIndexable(catName, region, total);
  const photos = (a) => sortedPhotos(a).map((p) => photoUrl(p.storage_path));
  const image = (ads[0] && photos(ads[0])[0]) || SITE + "/logo.webp";

  let h = shell;
  h = h.replace(/<title>[\s\S]*?<\/title>/, () => `<title>${esc(pageTitle)}</title>`);
  h = h.replace(/<meta name="description" content="[^"]*">/, () => `<meta name="description" content="${esc(desc)}">`);
  h = h.replace(/<link rel="canonical" href="[^"]*">/, () => `<link rel="canonical" href="${esc(url)}">`);
  h = setMeta(h, "property", "og:url", url);
  h = setMeta(h, "property", "og:title", pageTitle);
  h = setMeta(h, "property", "og:description", desc);
  h = setMeta(h, "property", "og:image", image);
  h = setMeta(h, "name", "twitter:title", pageTitle);
  h = setMeta(h, "name", "twitter:description", desc);
  h = setMeta(h, "name", "twitter:image", image);
  if (ads[0]) h = h.replace(/<meta property="og:image:(width|height)" content="[^"]*">\n?/g, () => "");

  const crumbs = [["ChadAds", SITE + "/"]];
  if (catName) crumbs.push([label, SITE + browsePath(catName, null)]);
  if (R) crumbs.push([R.name, SITE + browsePath(catName, region)]);
  const ld = {
    "@context": "https://schema.org",
    "@graph": [
      { "@type": "CollectionPage", name: h1, description: desc, url },
      { "@type": "BreadcrumbList", itemListElement: crumbs.map(([name, item], i) => ({ "@type": "ListItem", position: i + 1, name, item })) },
      ...(ads.length ? [{ "@type": "ItemList", numberOfItems: total,
        itemListElement: ads.slice(0, 30).map((a, i) => ({ "@type": "ListItem", position: i + 1, url: SITE + adPath(a.id, a.title), name: a.title })) }] : []),
    ],
  };
  const landing = { cat: catName || null, region: region || null, regionName: R ? R.name : null, h1, intro };
  const headExtra =
    `<meta name="robots" content="${indexable ? "index,follow,max-image-preview:large" : "noindex,follow"}">\n` +
    `<script type="application/ld+json">${safeJson(ld)}</script>\n` +
    `<script>window.__LANDING__=${safeJson(landing)};</script>\n`;
  h = h.replace("</head>", () => headExtra + "</head>");

  const items = ads.map((a) => {
    const first = sortedPhotos(a)[0], ph = first ? photoUrl(first.storage_path) : "", th = first ? photoUrl(thumbPath(first.storage_path)) : "";
    const city = a.cities ? `${a.cities.name}, ${a.cities.state}` : "";
    // small copy in the list; older ads without one fall back to the full photo
    return `<li><a href="${esc(adPath(a.id, a.title))}">${ph ? `<img src="${esc(th)}" data-full="${esc(ph)}" onerror="this.onerror=null;this.src=this.dataset.full" alt="${esc(a.title)}" loading="lazy" width="200" height="150" style="width:100%;height:auto;aspect-ratio:4/3;object-fit:cover;border-radius:12px">` : ""}` +
      `<strong>${esc(money(a.price))}</strong> ${esc(a.title)}<br><small>${esc(city)}</small></a></li>`;
  }).join("\n");
  const catLinks = (cats || []).map((c) => `<a href="${browsePath(c.name, null)}">${esc(catLabel(c.name))}</a>`).join(" · ");
  const regLinks = REGION_ORDER.map((r) => `<a href="${browsePath(null, r)}">${esc(REGIONS[r].name)}</a>`).join(" · ");
  const article =
    `<article class="seo-list"><h1>${esc(h1)}</h1><p>${esc(intro)}</p>` +
    (ads.length ? `<ul style="list-style:none;padding:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:16px">${items}</ul>`
                : `<p>No ads here yet. <a href="/">Browse everything on ChadAds</a>, or sign in and list the first one.</p>`) +
    `<nav aria-label="More ways to browse"><h2>Browse by category</h2><p>${catLinks}</p><h2>Browse by region</h2><p>${regLinks}</p></nav></article>`;
  h = h.replace(/<main id="main">[\s\S]*?<\/main>/, () => `<main id="main">${article}</main>`);
  return { html: h, indexable };
}

// The sitemap: the plain pages, every category/region page that has enough ads, and one entry per active ad.
// "ads" need: id, title, created_at, categories{name}, cities{regions}.
export function buildSitemap(ads, todayIso) {
  const day = (iso) => String(iso || todayIso).slice(0, 10);
  const groups = new Map();   // address -> { n: how many ads, last: newest date, need: ads required }
  const bump = (path, need, when) => {
    const g = groups.get(path) || { n: 0, last: "", need };
    g.n++; if (when > g.last) g.last = when; groups.set(path, g);
  };
  for (const a of ads) {
    const cat = a.categories && a.categories.name, regs = (a.cities && a.cities.regions) || [], when = day(a.created_at);
    if (cat) bump(browsePath(cat, null), INDEX_MIN.category, when);
    for (const r of regs) {
      if (!REGIONS[r]) continue;
      bump(browsePath(null, r), INDEX_MIN.region, when);
      if (cat && r !== "upstate-new-york") bump(browsePath(cat, r), INDEX_MIN.combo, when);   // upstate combos duplicate the category page
    }
  }
  const fixed = [["/", "daily", "1.0"], ["/about", "monthly", "0.5"], ["/terms", "yearly", "0.3"], ["/privacy", "yearly", "0.3"]]
    .map(([p, f, pr]) => `  <url><loc>${SITE}${p}</loc><lastmod>${day(todayIso)}</lastmod><changefreq>${f}</changefreq><priority>${pr}</priority></url>`);
  const lists = [...groups.entries()].filter(([, g]) => g.n >= g.need).sort(([a], [b]) => (a < b ? -1 : 1))
    .map(([p, g]) => `  <url><loc>${esc(SITE + p)}</loc><lastmod>${g.last}</lastmod><changefreq>daily</changefreq><priority>0.8</priority></url>`);
  const adUrls = ads.map((a) => `  <url><loc>${esc(SITE + adPath(a.id, a.title))}</loc><lastmod>${day(a.created_at)}</lastmod><changefreq>weekly</changefreq><priority>0.7</priority></url>`);
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${[...fixed, ...lists, ...adUrls].join("\n")}\n</urlset>\n`;
}