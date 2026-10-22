// ChadAds dealer feed importer (a Supabase Edge Function).
// Reads each active feed (for example carsforsale.com), a CSV that can hold the cars of MANY dealers (the DealerID column). For every
// dealer that has been set up, it adds new cars, updates changed ones and marks cars that left the feed as sold. Unknown DealerIDs are ignored and reported.
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

// The feed's column names are matched ignoring capital letters (one export says "images", another "Images"; "NewUsed" or "NEWUSED").
const CANON = Object.fromEntries(["DealerID", "NEWUSED", "VIN", "StockNumber", "Make", "Model", "ModelYear", "Trim", "BodyStyle", "Mileage", "EngineDescription", "Cylinders", "FuelType", "Transmission", "Price", "ExteriorColor", "InteriorColor", "Options", "Description", "Images"].map((n) => [n.toLowerCase(), n]));

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
  const head = rows.shift().map((h) => { h = h.trim(); return CANON[h.toLowerCase()] || h; });
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
  if (/MOTORCYCLE|SCOOTER/i.test(body)) return "Motorcycles";
  if (/SNOWMOBILE/i.test(body)) return "Snowmobiles";
  if (/\bATV\b|\bUTV\b|SIDE.?BY.?SIDE/i.test(body)) return "ATV";
  if (/BOAT|PONTOON|WATERCRAFT|PERSONAL WATER/i.test(body)) return "Boats";
  if (/MOTOR ?HOME|TRAVEL TRAILER|CAMPER|FIFTH WHEEL|\bRV\b/i.test(body)) return "Campers";
  if (/TRAILER/i.test(body)) return "Trailers";
  if (TRUCK_RE.test(model) || /PICKUP|CREW ?CAB|EXT(ENDED)? ?CAB|REG(ULAR)? ?CAB|SUPER ?CAB|SUPER ?CREW|TRUCK/i.test(body)) return "Auto Trucks";
  if (SUV_RE.test(model) || /\bSUV\b|SPORT UTILITY/i.test(body)) return "Auto SUVs";
  return "Auto Cars";
}

// "Sport 4DR 4WD SUV" -> "Sport 4WD": door counts and body words are noise in a title (the category already says it).
const TRIM_NOISE = /\b[2-5]\s?dr\b|\b(suv|sedan|coupe|hatchback|wagon|convertible|roadster|pickup|crew cab|extended cab|regular cab|van|minivan)\b/gi;
export function titleFor(row) {
  const cleaned = String(row.Trim || "").replace(TRIM_NOISE, " ").replace(/\s+/g, " ").trim();
  const trim = cleaned || String(row.Trim || "").trim();   // if only body words were there ("Coupe" for a Business model), keep them
  const t = [row.ModelYear, niceCase(row.Make), niceCase(row.Model), niceCase(trim)].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
  return t.length > 60 ? t.slice(0, 59).replace(/\s+\S*$/, "") + "\u2026" : t;
}

// Dealers paste the same sales paragraph on every car. Sentences that match these are dropped. Add more here for other dealers.
const BOILERPLATE = [/our primary goal/i, /online dealership/i, /enhance the buying experience/i];
// Dealer descriptions often contain HTML. Turn line breaks into new lines, remove the other tags, and decode the common "&amp;" codes.
export function htmlToText(s) {
  return String(s || "")
    .replace(/<\s*br\s*\/?\s*>/gi, "\n").replace(/<\/\s*(p|div|li|h\d)\s*>/gi, "\n").replace(/<\s*li[^>]*>/gi, "- ")
    .replace(/<[^>]*>/g, "")
    .replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/&lt;/gi, "<").replace(/&gt;/gi, ">").replace(/&quot;/gi, '"').replace(/&#0?39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_, n) => { try { return String.fromCodePoint(+n); } catch (_e) { return ""; } })
    .replace(/[ \t\f\v]+/g, " ").replace(/ ?\n ?/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}
function salesLine(s) {
  const paragraphs = htmlToText(s).split("\n").map((p) => p.trim()).filter(Boolean);
  const kept = paragraphs.map((p) => p.split(/(?<=[.!?])\s+/).filter((x) => x && !BOILERPLATE.some((re) => re.test(x))).join(" ")).filter(Boolean);
  let out = kept.join("\n");
  if (out.length > 1400) out = out.slice(0, 1399).replace(/\s+\S*$/, "") + "\u2026";   // leave room for the specs and the dealer line (the ad limit is 2000)
  return out;
}

export function descriptionFor(row, dealer) {
  const lines = [];
  const sales = salesLine(row.Description);
  if (sales) lines.push(sales);
  const miles = Number(row.Mileage);
  const cond = String(row.NEWUSED).toUpperCase() === "N" ? "New" : "Used";
  lines.push(`${titleFor(row)} (${cond}${miles > 0 ? ", " + miles.toLocaleString("en-US") + " miles" : ""}).`);
  const spec = [];
  const real = (v) => v && !/^(unspecified|unknown|n\/a|none)$/i.test(String(v).trim());
  if (real(row.EngineDescription)) spec.push("Engine: " + row.EngineDescription);
  if (real(row.Transmission)) spec.push("Transmission: " + row.Transmission);
  if (real(row.FuelType)) spec.push("Fuel: " + row.FuelType);
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

// A car's ID in ChadAds: its real 17-character VIN, or "STK-" plus the stock number when there is no usable VIN (classic cars, motorcycles...).
// Empty means the row cannot be tracked and is skipped.
export function idFor(row) {
  const vin = String(row.VIN || "").replace(/\s/g, "").toUpperCase();
  if (/^[A-HJ-NPR-Z0-9]{17}$/.test(vin)) return vin;
  const stock = String(row.StockNumber || "").replace(/\s+/g, " ").trim().toUpperCase();
  return stock ? "STK-" + stock.slice(0, 40) : "";
}

// One feed row -> the fields of a ChadAds ad (plus the photo links).
export function mapRow(row, dealer) {
  const price = Math.round(Number(String(row.Price).replace(/[^0-9.]/g, "")) || 0);
  return {
    external_id: idFor(row),
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

// ===== I/O (talks to the database and the dealers' server; not part of the browser test) =====
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const BUCKET = "listing-photos", MAX_PHOTOS = 5, MAX_PHOTO_BYTES = 5 * 1024 * 1024, TIME_BUDGET_MS = 100_000;
// The admin page calls this function from chadads.com, so the browser first sends a harmless "preflight" (OPTIONS) check. It must be answered with these headers.
// (This does not open anything up: every real request still needs the secret or an admin login.)
const CORS = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, apikey, content-type, x-client-info, x-import-secret", "access-control-allow-methods": "POST, OPTIONS" };
const json = (o, status = 200) => new Response(JSON.stringify(o, null, 2), { status, headers: { ...CORS, "content-type": "application/json" } });

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

// One dealer's cars from the feed -> their ads.
async function processDealer(supabase, dealerCfg, rows, catId, dry, deadline) {
  const out = { dealer: dealerCfg.name, code: dealerCfg.code, rows: rows.length, created: 0, updated: 0, unchanged: 0, sold: 0, reactivated: 0, hidden: 0, waiting: 0, deferred: 0, skipped: 0, photosCopied: 0, notes: [], preview: [] };
  const dealer = { name: dealerCfg.name, place: `${dealerCfg.city_name}, ${dealerCfg.state}` };
  const existing = await supabase.from("listings").select("id,external_id,status,feed_hash,listing_photos(id)").eq("seller_id", dealerCfg.seller_id).not("external_id", "is", null).limit(5000);
  if (existing.error) { out.notes.push("Could not read existing ads: " + existing.error.message); return out; }
  const byVin = new Map((existing.data || []).map((l) => [l.external_id, l]));
  const activeNow = (existing.data || []).filter((l) => l.status === "active").length;

  // Safety: a broken, empty or half-size file must never wipe out a dealer's ads.
  if (!rows.length) { out.notes.push("This dealer has no cars in the feed right now, so nothing was changed."); return out; }
  if (activeNow >= 10 && rows.length < activeNow * 0.5) { out.notes.push(`The feed has ${rows.length} cars for this dealer but ${activeNow} are listed, so nothing was changed (looks wrong).`); return out; }

  // RULE: a dealer car with no pictures is not shown. It waits (status "hidden", see step29_hidden_status.sql) until the feed has photos for it.
  const seen = new Set();
  for (const row of rows) {
    const m = mapRow(row, dealer);
    if (!m.external_id || !m.title || !catId[m.category]) { out.skipped++; continue; }
    if (seen.has(m.external_id)) { out.skipped++; continue; }
    seen.add(m.external_id);
    const h = await hashesFor(m, dealerCfg.city_id);
    const have = byVin.get(m.external_id);
    const nPhotos = have ? (have.listing_photos || []).length : 0;
    if (out.preview.length < 6) out.preview.push({ vin: m.external_id, category: m.category, title: m.title, price: m.price_on_request ? "Call for price" : m.price, photos: m.photos.length, action: !m.photos.length && nPhotos === 0 ? "wait (no photos)" : !have ? "create" : have.feed_hash === h.combined && nPhotos > 0 ? "unchanged" : "update", description: m.description.slice(0, 400) });
    const fields = { category_id: catId[m.category], city_id: dealerCfg.city_id, title: m.title, description: m.description, price: m.price, price_on_request: m.price_on_request, status: "active", feed_hash: h.combined };

    if (!have) {
      if (!m.photos.length) { out.waiting++; continue; }          // no pictures yet: do not publish
      if (dry) { out.created++; continue; }
      if (Date.now() > deadline) { out.deferred++; continue; }   // out of time: the next run picks this car up
      const ins = await supabase.from("listings").insert({ ...fields, seller_id: dealerCfg.seller_id, external_id: m.external_id, is_demo: false }).select("id").single();
      if (ins.error) { out.skipped++; out.notes.push(`${m.external_id}: ${ins.error.message}`); continue; }
      const ph = await replacePhotos(supabase, dealerCfg.seller_id, ins.data.id, m.photos);
      if (ph.ok) { out.created++; out.photosCopied += ph.count; }
      else {
        // The feed has photo links but none could be copied right now: keep the car hidden and try again on the next run.
        await supabase.from("listings").update({ status: "hidden", feed_hash: h.fields + "|" }).eq("id", ins.data.id);
        out.waiting++;
      }
    } else {
      if (!m.photos.length && nPhotos === 0) {                    // no pictures at all: do not show it
        if (have.status === "active") { out.hidden++; if (!dry) await supabase.from("listings").update({ status: "hidden" }).eq("id", have.id); }
        else out.waiting++;
        continue;
      }
      const wasHash = (have.feed_hash || "").split("|"), same = have.feed_hash === h.combined;
      const needPhotos = m.photos.length > 0 && (nPhotos === 0 || wasHash[1] !== h.photos);
      if (same && have.status === "active" && !(m.photos.length && nPhotos === 0)) { out.unchanged++; continue; }
      if (dry) { out.updated++; continue; }
      if (Date.now() > deadline) { out.deferred++; continue; }
      let photoNote = null;
      if (needPhotos) {
        const ph = await replacePhotos(supabase, dealerCfg.seller_id, have.id, m.photos);
        out.photosCopied += ph.count;
        if (!ph.ok) { fields.feed_hash = h.fields + "|" + (wasHash[1] || ""); photoNote = "photos kept"; }
        if (nPhotos === 0 && ph.count === 0) fields.status = "hidden";   // still no pictures
      }
      const up = await supabase.from("listings").update(fields).eq("id", have.id);
      if (up.error) { out.skipped++; out.notes.push(`${m.external_id}: ${up.error.message}`); continue; }
      if (fields.status === "hidden") out.waiting++;
      else if (have.status !== "active") out.reactivated++;
      else out.updated++;
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

// One feed file (for example carsforsale.com) -> split by DealerID -> each known dealer's cars.
// "uploaded" is the text of a file the admin uploaded (the feed link is not used then); otherwise the feed link is fetched.
async function runSource(supabase, src, dry, deadline, uploaded) {
  const out = { source: src.name, rows: 0, dealers: [], unknown: [], notes: [], info: [] };
  let text;
  if (uploaded != null) text = uploaded;
  else if (!src.feed_url) { out.notes.push("This feed has no link set. You can still upload a file (or let the GitHub job deliver it)."); return out; }
  else {
    const res = await fetch(src.feed_url, { signal: AbortSignal.timeout(60000) });
    if (!res.ok) { out.notes.push(`Could not read the feed (HTTP ${res.status}).`); return out; }
    text = await res.text();
  }
  if (text.length > 25 * 1024 * 1024) { out.notes.push("The feed file is too big (over 25 MB)."); return out; }
  const rows = parseCsv(text);
  out.rows = rows.length;
  if (!rows.length) { out.notes.push("The feed file has no cars, so nothing was changed."); return out; }
  const cats = await supabase.from("categories").select("id,name");
  const catId = Object.fromEntries((cats.data || []).map((c) => [c.name, c.id]));
  const dealers = src.dealers || [];
  const hasCode = "DealerID" in rows[0];
  const byCode = new Map(dealers.map((d) => [String(d.code), []]));
  const unknown = new Map();
  for (const r of rows) {
    // A feed without a DealerID column can only belong to a single dealer.
    const code = hasCode ? String(r.DealerID).trim() : (dealers.length === 1 ? String(dealers[0].code) : "");
    if (byCode.has(code)) byCode.get(code).push(r); else unknown.set(code || "(none)", (unknown.get(code || "(none)") || 0) + 1);
  }
  out.unknown = [...unknown].map(([code, cars]) => ({ code, cars }));
  for (const d of dealers) {
    try { out.dealers.push(await processDealer(supabase, d, byCode.get(String(d.code)) || [], catId, dry, deadline)); }
    catch (e) { out.dealers.push({ dealer: d.name, code: d.code, error: String((e && e.message) || e), rows: 0, notes: [] }); }
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  if (!(await isAllowed(req, supabase))) return json({ error: "not allowed" }, 401);
  const url = new URL(req.url), dry = url.searchParams.get("dry") === "1";

  // LIST DEALERS (admin page): ?dealers=1&source=<feed name>
  if (url.searchParams.get("dealers") === "1") {
    const g = await supabase.rpc("feed_get_source", { p_name: url.searchParams.get("source") || "" });
    if (g.error) return json({ error: "Run step23/step25 first (" + g.error.message + ")" }, 500);
    if (!g.data) return json({ error: "There is no feed with that name." }, 400);
    return json({ dealers: g.data.dealers || [] });
  }

  // ADD A DEALER (admin page form): creates a placeholder account nobody logs into, then links DealerID -> account -> town (step28_add_dealer.sql)
  if (url.searchParams.get("add_dealer") === "1") {
    let b; try { b = await req.json(); } catch (_) { return json({ error: "Bad request." }, 400); }
    const clean = (v, n) => String(v || "").trim().slice(0, n);
    const source = clean(b.source, 60), code = clean(b.code, 40), name = clean(b.name, 40), city = clean(b.city, 80), state = clean(b.state, 2).toUpperCase(), website = clean(b.website, 300);
    let email = clean(b.email, 120).toLowerCase();
    if (!source || !code || !name || !city || !/^[A-Z]{2}$/.test(state)) return json({ error: "Please fill in the feed name, DealerID, dealer name, town and two-letter state." }, 400);
    if (!/^[A-Za-z0-9._-]+$/.test(code)) return json({ error: "The DealerID may only contain letters, numbers, dots, dashes and underscores." }, 400);
    if (website && !/^https?:\/\/\S+$/i.test(website)) return json({ error: "The website must start with https://" }, 400);
    if (!email) email = `dealer-${code.toLowerCase()}@chadads.com`;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "That email address does not look right." }, 400);
    const created = await supabase.auth.admin.createUser({ email, password: crypto.randomUUID() + crypto.randomUUID(), email_confirm: true, user_metadata: { display_name: name } });
    if (created.error && !/already|registered|exists/i.test(created.error.message)) return json({ error: "Could not create the account: " + created.error.message }, 500);
    const r = await supabase.rpc("feed_add_dealer", { p_source: source, p_code: code, p_email: email, p_name: name, p_city: city, p_state: state, p_website: website || null });
    if (r.error) return json({ error: r.error.message }, 400);
    return json({ ok: true, message: r.data });
  }

  // CHECK MODE (the GitHub job): "is this the file you already imported?" ?check=1&source=<feed name>&stamp=<file name|time|size>
  if (url.searchParams.get("check") === "1") {
    const g = await supabase.rpc("feed_get_source", { p_name: url.searchParams.get("source") || "" });
    if (g.error) return json({ error: "Run step27_feed_stamp.sql first (" + g.error.message + ")" }, 500);
    if (!g.data) return json({ error: "There is no feed with that name." }, 400);
    const stamp = url.searchParams.get("stamp") || "";
    return json({ changed: !stamp || stamp !== (g.data.last_stamp || ""), last: g.data.last_stamp || null });
  }

  // UPLOAD MODE (admin page "Upload a feed file", and the GitHub job): the body of the request is the CSV text, the feed is named in ?source=.
  if (url.searchParams.get("upload") === "1") {
    const name = url.searchParams.get("source") || "";
    const body = await req.text();
    if (!body.trim()) return json({ error: "The file is empty." }, 400);
    if (body.length > 25 * 1024 * 1024) return json({ error: "The file is too big (over 25 MB)." }, 400);
    const g = await supabase.rpc("feed_get_source", { p_name: name });
    if (g.error) return json({ error: "Run step25_feed_upload.sql first (" + g.error.message + ")" }, 500);
    if (!g.data) return json({ error: `There is no feed called "${name}". Add it first (step23_dealer_feed.sql, section 6).` }, 400);
    let r;
    try { r = await runSource(supabase, g.data, dry, Date.now() + TIME_BUDGET_MS, body); }
    catch (e) { r = { source: g.data.name, error: String((e && e.message) || e), dealers: [], unknown: [], notes: [] }; }
    const fileName = (url.searchParams.get("filename") || "").slice(0, 120);
    if (fileName) r.file = { name: fileName, modified: Date.now(), size: body.length };
    if (!dry) {
      await saveResult(supabase, g.data, r, fileName ? "(file " + fileName + ") " : "(uploaded file) ");
      // The GitHub job passes the file's stamp. It is remembered only when every car was handled, so an unfinished big import is read again next time.
      const stamp = url.searchParams.get("stamp");
      const finished = !r.error && (r.dealers || []).every((d) => !d.error && !d.deferred);
      if (stamp && finished) await supabase.rpc("feed_save_stamp", { p_id: g.data.id, p_stamp: stamp });
    }

    return json({ dry, upload: true, results: [r] });
  }

  const cfg = await supabase.rpc("feed_get_config");
  if (cfg.error) return json({ error: "Run step23_dealer_feed.sql first (" + cfg.error.message + ")" }, 500);
  if (!cfg.data || !cfg.data.length) return json({ dry, message: "No active feed link. You can still use \"Upload a feed file\". To fetch a link automatically, set it and set active = true (step23_dealer_feed.sql, section 6)." });
  const deadline = Date.now() + TIME_BUDGET_MS, results = [];
  for (const src of cfg.data) {
    let r;
    try { r = await runSource(supabase, src, dry, deadline); }
    catch (e) { r = { source: src.name, error: String((e && e.message) || e), dealers: [], unknown: [], notes: [] }; }
    results.push(r);
    if (!dry) await saveResult(supabase, src, r, "");
  }
  return json({ dry, results });
});

// Writes a one-line summary of a run next to the feed, so you can see it later (select name, last_run_at, last_result from private.feed_sources).
async function saveResult(supabase, src, r, prefix) {
  const per = (r.dealers || []).map((d) => d.error ? `${d.dealer}: ERROR ${d.error}` : `${d.dealer}: ${d.rows} cars, +${d.created} ~${d.updated} =${d.unchanged} sold ${d.sold} back ${d.reactivated} hidden-no-photos ${d.hidden || 0} waiting-for-photos ${d.waiting || 0} deferred ${d.deferred} skipped ${d.skipped}${d.notes.length ? " (" + d.notes.slice(0, 3).join(" | ") + ")" : ""}`);
  const unk = (r.unknown || []).length ? ` UNKNOWN dealers in file: ${r.unknown.map((u) => u.code + " (" + u.cars + ")").join(", ")}.` : "";
  await supabase.rpc("feed_save_result", { p_id: src.id, p_result: prefix + (r.error ? "ERROR: " + r.error : per.join(" ; ")) + unk + (r.notes || []).join(" ") });
}
