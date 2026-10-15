// Sends the "you have a new message" email. Called by the database (see step20_email_alerts.sql), never by a visitor.
//   POST https://chadads.com/api/notify   header x-notify-secret: <NOTIFY_SECRET>   JSON body from the database trigger
// Two secrets live in Netlify (Site settings > Environment variables), never in this file:
//   NOTIFY_SECRET   the same long random text that is stored in the database
//   RESEND_API_KEY  the key from your Resend account
// The email is sent through Resend (resend.com) from notifications@chadads.com. See NOTES.md ("Email alerts").
import { esc, SITE } from "../edge-lib/seo.js";

const FROM = "ChadAds <notifications@chadads.com>";
const clip = (s, n) => { s = String(s ?? "").replace(/\s+/g, " ").trim(); return s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s; };
const json = (o, status) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

// Compares two texts without stopping at the first difference (so response time doesn't leak the secret).
function same(a, b) {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] || 0) ^ (y[i] || 0);
  return d === 0;
}

export default async (request) => {
  if (request.method !== "POST") return json({ error: "POST only" }, 405);
  const env = (k) => (typeof Netlify !== "undefined" && Netlify.env ? Netlify.env.get(k) : Deno.env.get(k));
  const secret = env("NOTIFY_SECRET"), key = env("RESEND_API_KEY");
  if (!secret || !key) {
    // Says which one is missing (names only, never values) so a setup mistake is easy to find.
    const missing = [!secret && "NOTIFY_SECRET", !key && "RESEND_API_KEY"].filter(Boolean);
    // Also the NAMES (never values) of variables that look related, to spot a typo or a stray space in a name.
    let seen = [];
    try {
      const all = typeof Netlify !== "undefined" && Netlify.env && Netlify.env.toObject ? Netlify.env.toObject() : Deno.env.toObject();
      seen = Object.keys(all).filter((k) => /notify|resend|secret|api_key/i.test(k)).map((k) => JSON.stringify(k));
      seen.push("(" + Object.keys(all).length + " variables visible in total)");
    } catch (e) { seen = ["could not list: " + String(e && e.message || e)]; }
    return json({ error: "not configured", missing, seen }, 503);
  }
  if (!same(request.headers.get("x-notify-secret") || "", secret)) return json({ error: "no" }, 401);

  let p;
  try { p = await request.json(); } catch (_) { return json({ error: "bad json" }, 400); }
  if (typeof p.to !== "string" || !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(p.to) || p.to.length > 254) return json({ error: "bad address" }, 400);
  const unsub = typeof p.unsubUrl === "string" && p.unsubUrl.startsWith(SITE + "/unsubscribe?") ? p.unsubUrl : null;

  const from = clip(p.fromName || "Someone", 40), title = clip(p.adTitle || "your ad", 80), body = clip(p.body, 300);
  const offer = Number.isFinite(+p.offer) && +p.offer > 0 ? Math.round(+p.offer) : null;
  const cid = Number.isInteger(+p.conversationId) ? +p.conversationId : "";
  const link = `${SITE}/?messages=${cid}`;
  const what = offer ? `an offer of $${offer.toLocaleString("en-US")}` : "a message";
  const subject = offer ? `${from} offered $${offer.toLocaleString("en-US")} on ${clip(title, 50)}` : `New message from ${from} about ${clip(title, 50)}`;
  const hi = p.toName ? `Hi ${clip(p.toName, 40)},` : "Hi,";

  const text = `${hi}\n\n${from} sent you ${what} about "${title}" on ChadAds:\n\n${offer ? "Offer: $" + offer.toLocaleString("en-US") + "\n" : ""}${body}\n\nRead it and reply on ChadAds: ${link}\n\nPlease reply on ChadAds. Replying to this email will not reach them.\n` +
    (unsub ? `\nDon't want these emails? Turn them off: ${unsub}\n` : "");
  const html = `<!doctype html><html><body style="margin:0;background:#f4efe4;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1e1c19">
<div style="max-width:520px;margin:0 auto;padding:24px 16px">
  <div style="background:#fbf7ef;border-radius:16px;padding:28px 24px;border-bottom:6px solid #e95e0d">
    <p style="margin:0 0 16px;font-size:20px;font-weight:800;color:#e95e0d">ChadAds</p>
    <p style="margin:0 0 14px;font-size:16px">${esc(hi)}</p>
    <p style="margin:0 0 14px;font-size:16px"><strong>${esc(from)}</strong> sent you ${esc(what)} about <strong>${esc(title)}</strong>:</p>
    <div style="background:#fff;border-radius:12px;padding:14px 16px;margin:0 0 20px;font-size:16px;line-height:1.45">${offer ? `<div style="font-weight:800;color:#e95e0d;margin-bottom:6px">Offer: $${esc(offer.toLocaleString("en-US"))}</div>` : ""}${esc(body).replace(/\n/g, "<br>")}</div>
    <p style="margin:0 0 20px"><a href="${esc(link)}" style="display:inline-block;background:#e95e0d;color:#1e1c19;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:999px">View message</a></p>
    <p style="margin:0;font-size:13px;color:#5b5446">Please reply on ChadAds. Replying to this email will not reach them.</p>
  </div>
  ${unsub ? `<p style="margin:14px 0 0;font-size:12px;color:#5b5446;text-align:center">Don't want these emails? <a href="${esc(unsub)}" style="color:#5b5446">Turn them off</a>.</p>` : ""}
</div></body></html>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({
      from: FROM, to: [p.to], subject, html, text,
      ...(unsub ? { headers: { "List-Unsubscribe": `<${unsub}>` } } : {}),
    }),
  });
  if (!res.ok) return json({ error: "send failed", status: res.status }, 502);
  return json({ ok: true }, 200);
};

export const config = { path: "/api/notify" };
