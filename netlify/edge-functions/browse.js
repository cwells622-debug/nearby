// Builds the category and region pages:
//   chadads.com/for-sale/autos-trucks                      all trucks
//   chadads.com/in/capital-district                        everything in a region
//   chadads.com/for-sale/autos-trucks/capital-district     trucks in a region
// Logic lives in ../edge-lib/seo.js. Regions come from the database (cities.regions, see step15_regions.sql). See SEO.md.
import { SB_URL, SB_KEY, slugify, parseBrowsePath, buildListPage } from "../edge-lib/seo.js";

const HEADERS = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` };
const html = (body, status, extra = {}) =>
  new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8", ...extra } });

async function notFound(origin) {
  let body = "<h1>Not found</h1>";
  try { body = await (await fetch(origin + "/404.html")).text(); } catch (_) { /* keep the plain text */ }
  return html(body, 404, { "x-robots-tag": "noindex", "cache-control": "public, max-age=0, must-revalidate" });
}
const unavailable = () => html("Temporarily unavailable. Please try again.", 503, { "retry-after": "60", "x-robots-tag": "noindex" });

export default async (request) => {
  const url = new URL(request.url);
  const route = parseBrowsePath(url.pathname);
  if (!route) return notFound(url.origin);

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

  // The ads for this page: newest first, with the first photo, and a total count from the same query.
  let q = `${SB_URL}/rest/v1/listings?select=id,title,price,created_at,categories!inner(name,active),cities!inner(name,state,regions),listing_photos(id,storage_path,position)` +
    `&categories.active=eq.true&order=created_at.desc&limit=48`;
  if (catName) q += `&categories.name=eq.${encodeURIComponent(catName)}`;
  if (route.region) q += `&cities.regions=cs.${encodeURIComponent("{" + route.region + "}")}`;
  const ar = await fetch(q, { headers: { ...HEADERS, Prefer: "count=exact" } });
  if (!ar.ok) return unavailable();
  const ads = await ar.json();
  const total = parseInt((ar.headers.get("content-range") || "").split("/")[1], 10) || ads.length;

  const shellRes = await fetch(url.origin + "/index.html");
  if (!shellRes.ok) return unavailable();
  const { html: page } = buildListPage(await shellRes.text(), { catName, region: route.region, ads, total, cats });

  return html(page, 200, {
    "cache-control": "public, max-age=0, must-revalidate",
    "netlify-cdn-cache-control": "public, s-maxage=300, stale-while-revalidate=3600",
  });
};

export const config = { path: ["/for-sale/*", "/in/*"], cache: "manual" };
