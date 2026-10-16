// Builds the category and region pages:
//   chadads.com/for-sale/auto-trucks                      all trucks
//   chadads.com/in/capital-district                        everything in a region
//   chadads.com/for-sale/auto-trucks/capital-district     trucks in a region
//   chadads.com/in/north-creek-ny                          a town (/in/ + the town name + the state)
// Logic lives in ../edge-lib/seo.js. Regions come from the database (cities.regions, see step15_regions.sql). See SEO.md.
import { SB_URL, SB_KEY, slugify, parseBrowsePath, buildListPage, cityPath } from "../edge-lib/seo.js";

const HEADERS = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` };
const html = (body, status, extra = {}) =>
  new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8", ...extra } });

async function notFound(origin) {
  let body = "<h1>Not found</h1>";
  try { body = await (await fetch(origin + "/404.html")).text(); } catch (_) { /* keep the plain text */ }
  return html(body, 404, { "x-robots-tag": "noindex", "cache-control": "public, max-age=0, must-revalidate" });
}
const unavailable = () => html("Temporarily unavailable. Please try again.", 503, { "retry-after": "60", "x-robots-tag": "noindex" });

// "north-creek-ny" -> the matching row in the cities table, null if there is none, undefined if the database could not be reached.
// Town names are matched on their first letters, then checked exactly against the address we would build for each (cityPath).
async function findCity(slug) {
  const m = slug.match(/^(.*)-([a-z]{2})$/);
  if (!m) return null;
  const prefix = m[1].split("-")[0].slice(0, 3);
  const res = await fetch(`${SB_URL}/rest/v1/cities?select=id,name,state,lat,lng,regions&state=eq.${m[2].toUpperCase()}&name=ilike.${encodeURIComponent(prefix)}*&limit=1000`, { headers: HEADERS });
  if (!res.ok) return undefined;
  const rows = await res.json();
  return rows.find((c) => cityPath(c.name, c.state) === "/in/" + slug) || null;
}

export default async (request) => {
  const url = new URL(request.url);
  const route = parseBrowsePath(url.pathname);
  if (!route) return notFound(url.origin);
  // The two original category names had "Autos" in them; send old links and search results to the new addresses.
  const OLD = { "autos-cars": "auto-cars", "autos-trucks": "auto-trucks" };
  if (route.cat && OLD[route.cat]) {
    return new Response(null, { status: 301, headers: { location: url.origin + "/for-sale/" + OLD[route.cat] + (route.region ? "/" + route.region : ""), "cache-control": "public, max-age=3600" } });
  }

  // Which categories exist (and are switched on)?
  const cr = await fetch(`${SB_URL}/rest/v1/categories?select=id,name&active=eq.true&order=name`, { headers: HEADERS });
  if (!cr.ok) return unavailable();
  const cats = await cr.json();
  let catName = null;
  if (route.cat) {
    const found = cats.find((c) => slugify(c.name) === route.cat);
    if (!found) return notFound(url.origin);
    catName = found.name;
  }

  // A town page (/in/north-creek-ny): find the town, or say there is no such page.
  let city = null, nearby = false;
  if (route.citySlug) {
    city = await findCity(route.citySlug);
    if (city === undefined) return unavailable();
    if (!city) return notFound(url.origin);
  }

  // The ads for this page: newest first, with the first photo, and a total count from the same query.
  let q = `${SB_URL}/rest/v1/listings?select=id,title,price,price_on_request,created_at,categories!inner(name,active),cities!inner(name,state,regions),listing_photos(id,storage_path,position)` +
    `&categories.active=eq.true&order=created_at.desc&limit=48`;
  if (catName) q += `&categories.name=eq.${encodeURIComponent(catName)}`;
  if (route.region) q += `&cities.regions=cs.${encodeURIComponent("{" + route.region + "}")}`;
  const base = q;
  if (city) q += `&city_id=eq.${city.id}`;
  let ar = await fetch(q, { headers: { ...HEADERS, Prefer: "count=exact" } });
  if (!ar.ok) return unavailable();
  let ads = await ar.json();
  let total = parseInt((ar.headers.get("content-range") || "").split("/")[1], 10) || ads.length;
  // A town with no ads of its own shows the newest ads from about 25 miles around it (and is kept out of Google).
  if (city && total === 0) {
    const d = 0.36, dl = d / Math.cos((city.lat * Math.PI) / 180);
    ar = await fetch(base + `&cities.lat=gte.${city.lat - d}&cities.lat=lte.${city.lat + d}&cities.lng=gte.${city.lng - dl}&cities.lng=lte.${city.lng + dl}`, { headers: { ...HEADERS, Prefer: "count=exact" } });
    if (!ar.ok) return unavailable();
    ads = await ar.json();
    total = parseInt((ar.headers.get("content-range") || "").split("/")[1], 10) || ads.length;
    nearby = true;
  }

  const shellRes = await fetch(url.origin + "/index.html");
  if (!shellRes.ok) return unavailable();
  const { html: page } = buildListPage(await shellRes.text(), { catName, region: route.region, ads, total, cats, city, nearby });

  return html(page, 200, {
    "cache-control": "public, max-age=0, must-revalidate",
    "netlify-cdn-cache-control": "public, s-maxage=300, stale-while-revalidate=3600",
  });
};

export const config = { path: ["/for-sale/*", "/in/*"], cache: "manual" };
