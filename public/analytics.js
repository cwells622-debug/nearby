// ChadAds visit counting: Cloudflare Web Analytics (no cookies, no ads, no tracking across other sites).
//
// TO TURN IT ON: paste the site's token between the quotes on the TOKEN line, then push the site.
// Find it in Cloudflare: Web Analytics -> your site -> "Manage site" / the JavaScript snippet.
// It is the long code after  "token":  in the snippet. (The token is meant to be public; it is not a password.)
//
// While TOKEN is empty this file does nothing at all.
(function () {
  var TOKEN = "da70eb79135e4118a3d6e9e84f3ac6d1";
  var GA_ID = "G-JFWZE93NQJ";   // Google Analytics 4 measurement ID (public, not a secret). Sets Google's analytics cookies.

  // Only the real site is counted (not the old netlify.app address, previews or local testing).
  var h = location.hostname;
  if (h !== "chadads.com" && h !== "www.chadads.com") return;

  // Your own visits: open  https://chadads.com/?noanalytics=1  once in each browser you use (and ?noanalytics=0 to count it again).
  // Visiting the admin page does the same automatically.
  try {
    var m = location.search.match(/[?&]noanalytics=([01])/);
    if (m) { if (m[1] === "1") localStorage.setItem("chadads-no-analytics", "1"); else localStorage.removeItem("chadads-no-analytics"); }
    if (localStorage.getItem("chadads-no-analytics") === "1") return;
  } catch (e) { /* storage blocked: just count the visit */ }

  // Respect the browser's "Do Not Track" setting.
  if (navigator.doNotTrack === "1" || window.doNotTrack === "1") return;

  if (TOKEN) {
    var s = document.createElement("script");
    s.type = "module"; // same as Cloudflare's current snippet
    s.src = "https://static.cloudflareinsights.com/beacon.min.js";
    s.setAttribute("data-cf-beacon", JSON.stringify({ token: TOKEN }));
    document.head.appendChild(s);
  }

  // Google Analytics 4 (same rules as above: real site only, not the owner, not Do Not Track)
  if (GA_ID) {
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag("js", new Date());
    window.gtag("config", GA_ID);
    var g = document.createElement("script");
    g.async = true;
    g.src = "https://www.googletagmanager.com/gtag/js?id=" + GA_ID;
    document.head.appendChild(g);
  }
})();
