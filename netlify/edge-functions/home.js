// The home page (chadads.com/): the normal page, plus a plain list of the newest ads and links to every category and region
// in the HTML itself. The ads on screen are drawn by JavaScript, so without this the page that search engines trust most
// would carry no links to any ad. The app replaces this text as soon as it loads. Logic lives in ../edge-lib/seo.js (homeExtras).
// Safe by design: if anything goes wrong, the normal home page is returned untouched. See SEO.md.
import { SB_URL, SB_KEY, homeExtras } from "../edge-lib/seo.js";

const HEADERS = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` };

export default async (request, context) => {
  const res = await context.next();
  try {
    if (request.method !== "GET" || res.status !== 200 || !(res.headers.get("content-type") || "").includes("text/html")) return res;
    const [ar, cr] = await Promise.all([
      fetch(`${SB_URL}/rest/v1/listings?select=id,title,price,price_on_request,categories!inner(name,active),cities(name,state)&categories.active=eq.true&order=featured.desc,created_at.desc&limit=60`, { headers: HEADERS }),
      fetch(`${SB_URL}/rest/v1/categories?select=id,name&active=eq.true&order=name`, { headers: HEADERS }),
    ]);
    if (!ar.ok || !cr.ok) return res;
    const ads = await ar.json(), cats = await cr.json();
    const body = await res.clone().text();
    const out = body.replace(/(<h1 class="seo-intro">[\s\S]*?<\/h1>)/, (m) => m + homeExtras(ads, cats));
    if (out === body) return res;
    const headers = new Headers(res.headers);
    headers.delete("content-length");
    headers.delete("content-encoding");
    headers.set("cache-control", "public, max-age=0, must-revalidate");
    headers.set("netlify-cdn-cache-control", "public, s-maxage=300, stale-while-revalidate=3600");
    return new Response(out, { status: 200, headers });
  } catch (_) {
    return res;
  }
};

export const config = { path: "/", cache: "manual" };
