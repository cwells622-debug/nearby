// Builds one page per dealer:  chadads.com/dealer/tri-city-auto-sales  lists every active ad from that dealer.
// The address is the dealer's display name (slugified). Logic lives in ../edge-lib/seo.js (buildDealerPage).
import { SB_URL, SB_KEY, slugify, buildDealerPage } from "../edge-lib/seo.js";

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
  const parts = url.pathname.replace(/\/+$/, "").split("/").filter(Boolean);
  if (parts[0] !== "dealer" || parts.length !== 2) return notFound(url.origin);
  const slug = parts[1];

  // Dealers are few, so fetch them all and match on the slugified name.
  const dr = await fetch(`${SB_URL}/rest/v1/profiles?select=id,display_name,dealer_website&is_dealer=eq.true&limit=1000`, { headers: HEADERS });
  if (!dr.ok) return unavailable();
  const dealer = (await dr.json()).find((d) => slugify(d.display_name) === slug);
  if (!dealer) return notFound(url.origin);

  const ar = await fetch(
    `${SB_URL}/rest/v1/listings?select=id,title,price,price_on_request,created_at,categories!inner(name,active),cities(name,state),listing_photos(id,storage_path,position)` +
    `&seller_id=eq.${dealer.id}&status=eq.active&categories.active=eq.true&order=created_at.desc&limit=500`,
    { headers: { ...HEADERS, Prefer: "count=exact" } });
  if (!ar.ok) return unavailable();
  const ads = await ar.json();
  const total = parseInt((ar.headers.get("content-range") || "").split("/")[1], 10) || ads.length;

  return html(buildDealerPage(dealer, ads, total), 200, {
    "cache-control": "public, max-age=0, must-revalidate",
    "netlify-cdn-cache-control": "public, s-maxage=300, stale-while-revalidate=3600",
  });
};

export const config = { path: "/dealer/*", cache: "manual" };
