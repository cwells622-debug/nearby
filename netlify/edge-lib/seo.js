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
  "categories(name,active),cities(name,state)," +
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
export const sortedPhotos = (ad) =>
  [...(ad.listing_photos || [])].sort((a, b) => (a.position - b.position) || (a.id - b.id));

// Makes JSON safe to sit inside a <script> tag.
const safeJson = (o) => JSON.stringify(o).replace(/</g, "\\u003c").replace(new RegExp("[" + String.fromCharCode(0x2028, 0x2029) + "]", "g"), "");

// Replaces one meta tag's content (the tag is found by its name= or property= label).
function setMeta(html, attr, label, content) {
  const re = new RegExp(`<meta ${attr}="${label}" content="[^"]*">`);
  return html.replace(re, () => `<meta ${attr}="${label}" content="${esc(content)}">`);
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
    `<p>Listed by ${esc(seller)} on ChadAds. <a href="/">Browse more local classifieds</a>.</p></article>`;
  h = h.replace(/<main id="main">[\s\S]*?<\/main>/, () => `<main id="main">${article}</main>`);
  return h;
}

// The sitemap: the plain pages plus one entry per active ad.
export function buildSitemap(ads, todayIso) {
  const day = (iso) => String(iso || todayIso).slice(0, 10);
  const fixed = [
    ["/", "daily", "1.0"], ["/about", "monthly", "0.5"], ["/terms", "yearly", "0.3"], ["/privacy", "yearly", "0.3"],
  ].map(([p, f, pr]) => `  <url><loc>${SITE}${p}</loc><lastmod>${day(todayIso)}</lastmod><changefreq>${f}</changefreq><priority>${pr}</priority></url>`);
  const adUrls = ads.map(
    (a) => `  <url><loc>${esc(SITE + adPath(a.id, a.title))}</loc><lastmod>${day(a.created_at)}</lastmod><changefreq>weekly</changefreq><priority>0.7</priority></url>`
  );
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${[...fixed, ...adUrls].join("\n")}\n</urlset>\n`;
}
