// Builds a real, readable web page for each ad at  chadads.com/ad/38-2017-jeep-rubicon
// so Google, Facebook, WhatsApp and others can see the ad (title, price, photo, description).
// Runs on Netlify's edge. Logic lives in ../edge-lib/seo.js. See SEO.md.
import { SB_URL, SB_KEY, AD_SELECT, adPath, buildAdPage } from "../edge-lib/seo.js";

const html = (body, status, extra = {}) =>
  new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8", ...extra } });

// The branded "not found" page, marked so search engines don't index it.
async function notFound(origin) {
  let body = "<h1>Not found</h1>";
  try { body = await (await fetch(origin + "/404.html")).text(); } catch (_) { /* keep the plain text */ }
  return html(body, 404, { "x-robots-tag": "noindex", "cache-control": "public, max-age=0, must-revalidate" });
}

export default async (request) => {
  const url = new URL(request.url);
  const m = url.pathname.match(/^\/ad\/(\d{1,12})(?:-[^/]*)?\/?$/);
  if (!m) return notFound(url.origin);

  // Ask the database for this ad. The public key can only see what the site's own visitors can see
  // (active ads), so sold or deleted ads simply come back empty.
  const res = await fetch(`${SB_URL}/rest/v1/listings?id=eq.${m[1]}&select=${AD_SELECT}`, {
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` },
  });
  if (!res.ok) return html("Temporarily unavailable. Please try again.", 503, { "retry-after": "60", "x-robots-tag": "noindex" });
  const ad = (await res.json())[0];
  if (!ad || (ad.categories && ad.categories.active === false)) return notFound(url.origin);

  // One address per ad: if the words in the address are old or wrong, send to the right one.
  const want = adPath(ad.id, ad.title);
  if (url.pathname.replace(/\/$/, "") !== want) return Response.redirect(url.origin + want, 301);

  // Take the normal site page and fill in this ad's details.
  const shellRes = await fetch(url.origin + "/index.html");
  if (!shellRes.ok) return html("Temporarily unavailable. Please try again.", 503, { "retry-after": "60", "x-robots-tag": "noindex" });
  const page = buildAdPage(await shellRes.text(), ad);

  return html(page, 200, {
    "cache-control": "public, max-age=0, must-revalidate",
    // Netlify keeps a copy for 5 minutes, so a burst of visitors or bots costs almost nothing.
    "netlify-cdn-cache-control": "public, s-maxage=300, stale-while-revalidate=3600",
  });
};

export const config = { path: "/ad/*", cache: "manual" };
