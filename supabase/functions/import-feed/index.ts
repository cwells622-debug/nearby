// ChadAds dealer feed importer (a Supabase Edge Function).
// Reads each active dealer's inventory file (CSV), then adds new cars, updates changed ones and marks cars that left the feed as sold.
// Cars are matched by VIN, so running it again never duplicates anything. See NOTES.md ("Dealer feed import").
//
// HOW IT IS CALLED
//   * by the schedule (pg_cron), with the header  x-import-secret  (the secret stored in the database), or
//   * by an admin (the "Dealer feeds" buttons on the admin page), with the admin's login.
//   Add  ?dry=1  to PREVIEW: it reads and maps everything and says what it WOULD do, but changes nothing.
//
// This file has two halves. The first half is plain functions that do the mapping (no network). It can be tested by pasting it
// into a browser. The second half, below the marker line, talks to the database and the dealer's server.

// ======================================================================
// MAPPING (pure functions, no network)
// ======================================================================

// Reads a CSV file where every field may be in quotes and may contain commas. Returns [{header: value, ...}, ...].
export function parseCsv(text) {
  text = String(text).replace(/^﻿/, "").replace(/\r/g, "");
  const rows = []; let row = [], field = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; }
      else field += c;
    } else if (c === '"') q = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") { row.push(field); if (row.length > 1 || row[0] !== "") rows.push(row); row = []; field = ""; }
    else field += c;
  }
  if (field !== "" || row.length) { row.push(field); if (row.length > 1 || row[0] !== "") rows.push(row); }
  if (!rows.length) return [];
  const head = rows.shift().map((h) => h.trim());
  return rows.map((r) => Object.fromEntries(head.map((h, i) => [h, (r[i] ?? "").trim()])));
}

// "TOURING W/NAV." -> "Touring W/Nav.", "LX" stays "LX", "MR2" stays "MR2", "ACURA" -> "Acura".
const NAME_FIX = { KIA: "Kia", MINI: "Mini" };
export function niceCase(s) {
  s = String(s || "").trim();
  if (NAME_FIX[s.toUpperCase()]) return NAME_FIX[s.toUpperCase()];
  return s.split(/(\s+|\/)/).map((t) => {
    if (!t || /^(\s+|\/)$/.test(t)) return t;
    if (t.length <= 3 || /\d/.test(t)) return t.toUpperCase();
    return t.charAt(0).toUpperCase() + t.slice(1).toLowerCase();
  }).join("");
}

// Which ChadAds category a car belongs in. The feed's BodyStyle is only "4DR" or "5DR", so the model name decides.
const SUV_RE = /^(MDX|RDX|ZDX|CR-?V|PILOT|HR-?V|PASSPORT|RAV-?4|HIGHLANDER|4RUNNER|SEQUOIA|LAND CRUISER|C-?HR|VENZA|ESCAPE|EXPLORER|EDGE|EXPEDITION|BRONCO( SPORT)?|ECOSPORT|FLEX|TAHOE|SUBURBAN|EQUINOX|TRAVERSE|BLAZER|TRAX|TRAILBLAZER|ENVISION|WRANGLER( UNLIMITED)?|GRAND CHEROKEE( L)?|CHEROKEE|COMPASS|RENEGADE|PATRIOT|LIBERTY|COMMANDER|YUKON( XL)?|TERRAIN|ACADIA|ROGUE( SPORT)?|PATHFINDER|MURANO|ARMADA|KICKS|XTERRA|FORESTER|CROSSTREK|ASCENT|OUTBACK|TUCSON|SANTA FE|PALISADE|KONA|VENUE|SORENTO|SPORTAGE|TELLURIDE|SELTOS|CX-\d+|X[1-7]|GL[ABCEKS]|ML ?\d+|DURANGO|JOURNEY|NAVIGATOR( L)?|AVIATOR|CORSAIR|NAUTILUS|MKX|MKC|MKT|ENCLAVE|ENCORE|ESCALADE( ESV)?|XT[4-6]|TIGUAN|ATLAS|TOUAREG|XC ?\d+|RX( ?\d+\w*)?|GX( ?\d+)?|NX( ?\d+\w*)?|LX( ?\d+)?|UX|QX ?\d+|FX ?\d+|Q[3578]|GLB|RANGE ROVER.*|DISCOVERY.*)$/i;
const TRUCK_RE = /^(F-?\d{3}.*|SUPER DUTY.*|RANGER|MAVERICK|RAM( ?\d+)?.*|SILVERADO.*|SIERRA.*|COLORADO|CANYON|TACOMA|TUNDRA|FRONTIER|TITAN.*|RIDGELINE|GLADIATOR|TRANSIT.*|SPRINTER.*|PROMASTER.*|EXPRESS.*|SAVANA.*|E-?\d{3}.*)$/i;
export function categoryFor(row) {
  const model = String(row.Model || "").trim(), body = String(row.BodyStyle || "");
  if (TRUCK_RE.test(model) || /PICKUP|CREW ?CAB|EXT(ENDED)? ?CAB|REG(ULAR)? ?CAB|SUPER ?CAB|SUPER ?CREW|TRUCK/i.test(body)) return "Auto Trucks";
  if (SUV_RE.test(model) || /\bSUV\b|SPORT UTILITY/i.test(body)) return "Auto SUVs";
  return "Auto Cars";
}

export function titleFor(row) {
  const t = [row.ModelYear, niceCase(row.Make), niceCase(row.Model), niceCase(row.Trim)].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
  return t.length > 60 ? t.slice(0, 59).replace(/\s+\S*$/, "") + "…" : t;
}

// Dealers paste the same sales paragraph on every car. Sentences that match these are dropped. Add more here for other dealers.
const BOILERPLATE = [/our primary goal/i, /online dealership/i, /enhance the buying experience/i];
function salesLine(s) {
  const sentences = String(s || "").replace(/\s+/g, " ").trim().split(/(?<=[.!?])\s+/);
  return sentences.filter((x) => x && !BOILERPLATE.some((re) => re.test(x))).join(" ").trim();
}

export function descriptionFor(row, dealer) {
  const lines = [];
  const sales = salesLine(row.Description);
  if (sales) lines.push(sales);
  const miles = Number(row.Mileage);
  const cond = String(row.NEWUSED).toUpperCase() === "N" ? "New" : "Used";
  lines.push(`${titleFor(row)} (${cond}${miles > 0 ? ", " + miles.toLocaleString("en-US") + " miles" : ""}).`);
  const spec = [];
  if (row.EngineDescription) spec.push("Engine: " + row.EngineDescription);
  if (row.Transmission) spec.push("Transmission: " + row.Transmission);
  if (row.FuelType) spec.push("Fuel: " + row.FuelType);
  if (row.ExteriorColor) spec.push("Exterior: " + niceCase(row.ExteriorColor));
  if (row.InteriorColor) spec.push("Interior: " + niceCase(row.InteriorColor));
  if (spec.length) lines.push(spec.join(". ") + ".");
  const ids = [];
  if (row.StockNumber) ids.push("Stock #" + row.StockNumber);
  if (row.VIN) ids.push("VIN " + row.VIN);
  if (ids.length) lines.push(ids.join(". ") + ".");
  const feats = String(row.Options || "").split(",").map((x) => x.trim()).filter(Boolean).slice(0, 14);
  if (feats.length) lines.push("Features: " + feats.join(", ") + ".");
  if (dealer && dealer.name) lines.push(`Sold by ${dealer.name}${dealer.place ? ", " + dealer.place : ""}. Message us on ChadAds to ask about this vehicle.`);
  let d = lines.join("\n");
  if (d.length > 1990) d = d.slice(0, 1989).replace(/\s+\S*$/, "") + "…";
  return d;
}

// One feed row -> the fields of a ChadAds ad (plus the photo links).
export function mapRow(row, dealer) {
  const price = Math.round(Number(String(row.Price).replace(/[^0-9.]/g, "")) || 0);
  return {
    external_id: String(row.VIN || "").trim().toUpperCase(),
    category: categoryFor(row),
    title: titleFor(row),
    description: descriptionFor(row, dealer),
    price,
    price_on_request: price <= 0,   // no price in the feed -> "Call for price"
    photos: String(row.Images || "").split(",").map((u) => u.trim()).filter((u) => /^https?:\/\//i.test(u)),
  };
}

// A short fingerprint, to tell "this car changed" from "this car is the same as last time".
export async function fingerprint(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].slice(0, 8).map((b) => b.toString(16).padStart(2, "0")).join("");
}
export async function hashesFor(m, cityId) {
  const fields = await fingerprint(JSON.stringify([m.category, m.title, m.description, m.price, m.price_on_request, cityId]));
  const photos = await fingerprint(JSON.stringify(m.photos.slice(0, 5)));
  return { fields, photos, combined: fields + "|" + photos };
}

// ===== I/O (talks to the database and the dealer; not part of the browser test) =====
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const BUCKET = "listing-photos", MAX_PHOTOS = 5, MAX_PHOTO_BYTES = 5 * 1024 * 1024, TIME_BUDGET_MS = 100_000;
const json = (o, status = 200) => new Response(JSON.stringify(o, null, 2), { status, headers: { "content-type": "application/json" } });

async function isAllowed(req, supabase) {
  const secret = req.headers.get("x-import-secret");
  if (secret) {
    const { data } = await supabase.rpc("feed_check_secret", { s: secret });
    if (data === true) return true;
  }
  const jwt = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return false;
  const { data: u } = await supabase.auth.getUser(jwt);
  if (!u || !u.user) return false;
  const asUser = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_ANON_KEY"), { global: { headers: { Authorization: `Bearer ${jwt}` } } });
  const { data: admin } = await asUser.rpc("is_admin");
  return admin === true;
}

// Downloads one photo; returns { bytes, type, ext } or null if it is missing, too big, or not a JPG/PNG/WebP.
async function fetchPhoto(url) {
  const tries = [url]; if (/^http:/i.test(url)) tries.unshift(url.replace(/^http:/i, "https:"));
  for (const u of tries) {
    try {
      const res = await fetch(u, { redirect: "follow", signal: AbortSignal.timeout(15000) });
      if (!res.ok) continue;
      const type = (res.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
      const ext = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[type];
      if (!ext) continue;
      const bytes = new Uint8Array(await res.arrayBuffer());
      if (bytes.length < 500 || bytes.length > MAX_PHOTO_BYTES) continue;
      return { bytes, type, ext };
    } catch (_) { /* try the next address */ }
  }
  return null;
}

async function replacePhotos(supabase, sellerId, listingId, urls) {
  const old = await supabase.from("listing_photos").select("id,storage_path").eq("listing_id", listingId);
  const added = [];
  for (const url of urls.slice(0, MAX_PHOTOS)) {
    const p = await fetchPhoto(url);
    if (!p) continue;
    const path = `${sellerId}/${crypto.randomUUID()}.${p.ext}`;
    const up = await supabase.storage.from(BUCKET).upload(path, p.bytes, { contentType: p.type, upsert: false });
    if (!up.error) added.push(path);
  }
  if (urls.length && !added.length) return { ok: false, count: 0 };   // none of the photos could be fetched: keep the old ones
  if (old.data && old.data.length) {
    await supabase.from("listing_photos").delete().eq("listing_id", listingId);
    await supabase.storage.from(BUCKET).remove(old.data.map((r) => r.storage_path));
  }
  if (added.length) await supabase.from("listing_photos").insert(added.map((storage_path, position) => ({ listing_id: listingId, storage_path, position })));
  return { ok: true, count: added.length };
}

async function runFeed(supabase, feed, dry, deadline) {
  const out = { dealer: feed.dealer_name, rows: 0, created: 0, updated: 0, unchanged: 0, sold: 0, reactivated: 0, deferred: 0, skipped: 0, photosCopied: 0, notes: [], preview: [] };
  const res = await fetch(feed.feed_url, { signal: AbortSignal.timeout(60000) });
  if (!res.ok) { out.notes.push(`Could not read the feed (HTTP ${res.status}).`); return out; }
  const text = await res.text();
  if (text.length > 25 * 1024 * 1024) { out.notes.push("The feed file is too big (over 25 MB)."); return out; }
  const rows = parseCsv(text);
  out.rows = rows.length;
  const dealer = { name: feed.dealer_name, place: `${feed.city_name}, ${feed.state}` };

  const cats = await supabase.from("categories").select("id,name");
  const catId = Object.fromEntries((cats.data || []).map((c) => [c.name, c.id]));
  const existing = await supabase.from("listings").select("id,external_id,status,feed_hash").eq("seller_id", feed.seller_id).not("external_id", "is", null).limit(5000);
  if (existing.error) { out.notes.push("Could not read existing ads: " + existing.error.message); return out; }
  const byVin = new Map((existing.data || []).map((l) => [l.external_id, l]));
  const activeNow = (existing.data || []).filter((l) => l.status === "active").length;

  // Safety: a broken or empty file must never wipe out the dealer's ads.
  if (!rows.length) { out.notes.push("The feed has no cars, so nothing was changed."); return out; }
  if (activeNow >= 10 && rows.length < activeNow * 0.5) { out.notes.push(`The feed has ${rows.length} cars but ${activeNow} are listed, so nothing was changed (looks wrong).`); return out; }

  const seen = new Set();
  for (const row of rows) {
    const m = mapRow(row, dealer);
    if (!m.external_id || m.external_id.length < 11 || !m.title || !catId[m.category]) { out.skipped++; continue; }
    if (seen.has(m.external_id)) { out.skipped++; continue; }
    seen.add(m.external_id);
    const h = await hashesFor(m, feed.city_id);
    const have = byVin.get(m.external_id);
    if (out.preview.length < 6) out.preview.push({ vin: m.external_id, category: m.category, title: m.title, price: m.price_on_request ? "Call for price" : m.price, photos: m.photos.length, action: !have ? "create" : have.feed_hash === h.combined ? "unchanged" : "update", description: m.description.slice(0, 400) });
    const fields = { category_id: catId[m.category], city_id: feed.city_id, title: m.title, description: m.description, price: m.price, price_on_request: m.price_on_request, status: "active", feed_hash: h.combined };

    if (!have) {
      if (dry) { out.created++; continue; }
      if (Date.now() > deadline) { out.deferred++; continue; }   // out of time: the next run picks this car up
      const ins = await supabase.from("listings").insert({ ...fields, seller_id: feed.seller_id, external_id: m.external_id, is_demo: false }).select("id").single();
      if (ins.error) { out.skipped++; out.notes.push(`${m.external_id}: ${ins.error.message}`); continue; }
      const ph = await replacePhotos(supabase, feed.seller_id, ins.data.id, m.photos);
      out.created++; out.photosCopied += ph.count;
    } else {
      const wasHash = (have.feed_hash || "").split("|"), same = have.feed_hash === h.combined;
      if (same && have.status === "active") { out.unchanged++; continue; }
      if (dry) { out.updated++; continue; }
      if (Date.now() > deadline) { out.deferred++; continue; }
      let photoNote = null;
      if (wasHash[1] !== h.photos) {
        const ph = await replacePhotos(supabase, feed.seller_id, have.id, m.photos);
        out.photosCopied += ph.count;
        if (!ph.ok) { fields.feed_hash = h.fields + "|" + (wasHash[1] || ""); photoNote = "photos kept"; }
      }
      const up = await supabase.from("listings").update(fields).eq("id", have.id);
      if (up.error) { out.skipped++; out.notes.push(`${m.external_id}: ${up.error.message}`); continue; }
      if (have.status !== "active") out.reactivated++; else out.updated++;
      if (photoNote) out.notes.push(`${m.external_id}: ${photoNote}`);
    }
  }
  // Cars that are no longer in the feed were sold: hide them (the ad stays in the database as "sold").
  for (const [vin, l] of byVin) {
    if (seen.has(vin) || l.status !== "active") continue;
    out.sold++;
    if (!dry) await supabase.from("listings").update({ status: "sold" }).eq("id", l.id);
  }
  return out;
}

Deno.serve(async (req) => {
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  if (!(await isAllowed(req, supabase))) return json({ error: "not allowed" }, 401);
  const dry = new URL(req.url).searchParams.get("dry") === "1";
  const cfg = await supabase.rpc("feed_get_config");
  if (cfg.error) return json({ error: "Run step23_dealer_feed.sql first (" + cfg.error.message + ")" }, 500);
  if (!cfg.data || !cfg.data.length) return json({ dry, message: "No active dealer feeds. Add one (and set active = true) as described at the bottom of step23_dealer_feed.sql." });
  const deadline = Date.now() + TIME_BUDGET_MS, results = [];
  for (const feed of cfg.data) {
    let r;
    try { r = await runFeed(supabase, feed, dry, deadline); }
    catch (e) { r = { dealer: feed.dealer_name, error: String((e && e.message) || e) }; }
    results.push(r);
    if (!dry) {
      const summary = r.error ? "ERROR: " + r.error : `rows ${r.rows}: created ${r.created}, updated ${r.updated}, unchanged ${r.unchanged}, sold ${r.sold}, reactivated ${r.reactivated}, deferred ${r.deferred}, skipped ${r.skipped}. ${r.notes.slice(0, 5).join(" | ")}`;
      await supabase.rpc("feed_save_result", { p_id: feed.id, p_result: summary });
    }
  }
  return json({ dry, results });
});
