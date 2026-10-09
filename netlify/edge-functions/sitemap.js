// Builds sitemap.xml automatically from the live ads, so search engines hear about new ads without us editing a file.
import { SB_URL, SB_KEY, buildSitemap } from "../edge-lib/seo.js";

export default async () => {
  const ads = [];
  // 1000 rows per request is the database's limit; 10 rounds covers 10,000 ads. (Past that, split into several sitemaps.)
  for (let page = 0; page < 10; page++) {
    const res = await fetch(
      `${SB_URL}/rest/v1/listings?select=id,title,created_at,categories!inner(active)&categories.active=eq.true&order=id.desc&limit=1000&offset=${page * 1000}`,
      { headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` } }
    );
    if (!res.ok) return new Response("Temporarily unavailable", { status: 503, headers: { "retry-after": "300" } });
    const rows = await res.json();
    ads.push(...rows);
    if (rows.length < 1000) break;
  }
  return new Response(buildSitemap(ads, new Date().toISOString()), {
    headers: {
      "content-type": "application/xml; charset=utf-8",
      "cache-control": "public, max-age=0, must-revalidate",
      "netlify-cdn-cache-control": "public, s-maxage=3600, stale-while-revalidate=86400",
    },
  });
};

export const config = { path: "/sitemap.xml", cache: "manual" };
