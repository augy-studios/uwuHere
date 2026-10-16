// uwuHere service worker.
//
// BUMP VERSION ON EVERY CHANGE TO THIS SITE. Not once per release, and not only
// when this file itself changes: any edit under main-site/ means a new build,
// and a worker that is not bumped keeps serving the previous one to everybody
// who has visited before. vercel.json serves this file with
// Cache-Control: max-age=0, must-revalidate so the browser always fetches it,
// but the file has to actually differ for that to matter.
//
// ---------------------------------------------------------------------------
// What this file does, in the order the requests arrive
// ---------------------------------------------------------------------------
//
//   navigation to /host or /host.html      the cached host shell
//   navigation to /join or /join.html      the cached attendee shell
//   navigation to anything else            the cached home shell
//   /css/**, /js/**, icons, the manifest   cache first
//   Google Fonts                           cache first, kept across versions
//   /api/**                                network only, never cached
//   any other cross origin request         not intercepted at all
//   anything that is not a GET             not intercepted at all
//
// The pages carry their event code in ?id=, so one cached shell per page
// serves every event, and each page keeps its own last copy of the event in
// localStorage. That is what lets a host open their list with no connection.
//
// On localhost every one of those becomes network first, so an edit shows up
// on reload rather than after a version bump. See IS_DEV.
//
// ---------------------------------------------------------------------------
// The rules that are easy to break here
// ---------------------------------------------------------------------------
//
// **1. skipWaiting and clients.claim happen only when a person asks.** A new
// worker installs, then waits, and the update bar offers a reload. Neither call
// appears in install or activate. The page asks by posting `skip-waiting`, and
// that is the only route to either.
//
// **2. A response carrying `private` or `no-store` never enters the cache.**
// Every /api answer says no-store, and is never cached anyway. isCacheable()
// is the one gate every write goes through.
//
// **3. Nothing cross origin is cached except the font files.** PeerJS and its
// broker are left to the network on purpose (STUN-p2p-spec.md): check-in needs
// the network anyway, and a stale signalling library is worse than none.
//
// **4. A missing precache entry costs one file, not the feature.** Entries are
// added one at a time, not with cache.addAll, whose single bad path would fail
// the whole install. `node check-precache.js` keeps the list honest.
//
// VERSION is a plain integer, counting up by one.
const VERSION = 5;

const SHELL = `uwuHere-shell-${VERSION}`;
const FONTS = "uwuHere-fonts";

// Anything not in here is deleted on activate.
const KEEP = new Set([SHELL, FONTS]);

const IS_DEV =
  self.location.hostname === "localhost" ||
  self.location.hostname === "127.0.0.1" ||
  self.location.hostname === "[::1]";

/* -------------------------------------------------------------------------
 * The precache list
 *
 * Written by hand and checked by node check-precache.js.
 *
 * **The clean addresses, never the .html ones.** cleanUrls in vercel.json
 * makes /host.html a 308 to /host, and a response fetched through a redirect
 * cannot be served for a navigation: the installed app would fail to open.
 * ---------------------------------------------------------------------- */

const PRECACHE = [
  // The three pages.
  "/",
  "/host",
  "/join",

  // Styles.
  "/css/theme.css",
  "/css/app.css",

  // Every module. A precached page whose module is missing renders its markup
  // and then does nothing.
  "/js/home.js",
  "/js/host.js",
  "/js/join.js",
  "/js/shell.js",
  "/js/theme.js",
  "/js/icons.js",
  "/js/ui.js",
  "/js/tray.js",
  "/js/sw-update.js",
  "/js/api.js",
  "/js/store.js",
  "/js/geo.js",
  "/js/p2p.js",
  "/js/qr.js",
  "/js/password.js",
  // The Android app's side. Every page imports them through shell.js, and
  // in a browser they do nothing.
  "/js/app-bridge.js",
  "/js/app-update.js",
  "/js/app-notify.js",

  // The icons the interface itself uses, and the manifest.
  "/HAT-192.png",
  "/HAT-512.png",
  "/favicon.ico",
  "/manifest.json",
];

/* -------------------------------------------------------------------------
 * Install and activate
 * ---------------------------------------------------------------------- */

self.addEventListener("install", (event) => {
  event.waitUntil(fillShell());
  // No skipWaiting. The new worker waits until somebody accepts the update
  // prompt.
});

// `cache: 'reload'` on each request, or a bumped worker could fill its new
// cache from the browser's HTTP cache with the previous build's files.
async function fillShell() {
  const cache = await caches.open(SHELL);
  const failed = [];

  await Promise.all(
    PRECACHE.map(async (path) => {
      try {
        const response = await fetch(new Request(path, { cache: "reload" }));
        if (!response.ok) throw new Error(String(response.status));
        if (!isCacheable(response)) {
          throw new Error(
            response.redirected
              ? `redirected to ${response.url}, so the clean address belongs in PRECACHE`
              : "not cacheable"
          );
        }
        await cache.put(path, response);
      } catch (cause) {
        failed.push(`${path} (${cause?.message ?? cause})`);
      }
    })
  );

  if (failed.length > 0) {
    console.warn(
      `[uwuHere] ${failed.length} of ${PRECACHE.length} precache entries could not be stored. ` +
        `Offline is degraded, not off:\n  ${failed.join("\n  ")}`
    );
  }
}

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.filter((key) => !KEEP.has(key)).map((key) => caches.delete(key)));
    })()
  );
  // No clients.claim, for the same reason there is no skipWaiting above.
});

/* -------------------------------------------------------------------------
 * Talking to the page
 * ---------------------------------------------------------------------- */

self.addEventListener("message", (event) => {
  const data = event.data;
  const type = typeof data === "string" ? data : data?.type;

  if (type === "version") {
    const reply = { type: "version", version: VERSION };
    const port = event.ports?.[0];
    if (port) port.postMessage(reply);
    else event.source?.postMessage(reply);
    return;
  }

  // The one way either of these is ever called. sw-update.js posts it when the
  // reader presses Reload, and reloads on controllerchange.
  if (type === "skip-waiting") {
    event.waitUntil(self.skipWaiting().then(() => self.clients.claim()));
  }
});

/* -------------------------------------------------------------------------
 * Fetch
 * ---------------------------------------------------------------------- */

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  if (request.headers.has("range")) return;

  const url = new URL(request.url);

  if (url.origin !== self.location.origin) {
    if (url.hostname === "fonts.googleapis.com" || url.hostname === "fonts.gstatic.com") {
      event.respondWith(cacheFirst(request, FONTS));
    }
    return;
  }

  event.respondWith(handle(request, url));
});

async function handle(request, url) {
  if (url.pathname.startsWith("/api/")) return networkOnly(request);
  if (request.mode === "navigate") return navigation(request, url);
  return IS_DEV ? networkFirst(request) : cacheFirst(request, SHELL);
}

// Which cached shell answers a navigation. Both spellings of each page land
// on the one document cached under its clean address.
function shellFor(url) {
  const path = url.pathname.replace(/\/$/, "").replace(/\.html$/, "");
  if (path === "/host") return "/host";
  if (path === "/join") return "/join";
  return "/";
}

async function navigation(request, url) {
  const target = shellFor(url);

  if (IS_DEV) {
    try {
      return await fetch(request);
    } catch {
      return (await caches.match(target)) ?? lastResortPage();
    }
  }

  const cached = await caches.match(target);
  if (cached) return cached;

  try {
    return await fetch(request);
  } catch {
    // **Never a 503 for a navigation.** An installed app given one fails to
    // open at all rather than showing anything.
    return (await caches.match("/")) ?? lastResortPage();
  }
}

// For a navigation with nothing cached and no network. Built from a string
// because the case it exists for is an empty cache.
function lastResortPage() {
  return new Response(
    `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>uwuHere</title>
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
         background:#e4f7e4; color:#121815; font-family:"Jua","Segoe UI",sans-serif; padding:24px; }
  main { max-width:22rem; text-align:center; }
  h1 { font-size:1.25rem; margin:0 0 .5rem; color:#1f6b3d; }
  p { font-size:.95rem; line-height:1.5; margin:0 0 1.25rem; color:#3b453f; }
  button { font:inherit; padding:.7rem 1.4rem; border:1px solid rgba(255,255,255,.65);
           border-radius:999px; background:#ccffcc; color:#121815; cursor:pointer; }
</style>
</head>
<body>
  <main>
    <h1>uwuHere is not ready yet</h1>
    <p>It could not be opened offline, because it has not finished downloading.
       Connect to the internet once and it will open without a connection after that.</p>
    <button type="button" onclick="location.reload()">Try again</button>
  </main>
</body>
</html>`,
    { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
}

/* -------------------------------------------------------------------------
 * Strategies
 * ---------------------------------------------------------------------- */

// The same shape as every /api error, so js/api.js reads it as "offline".
async function networkOnly(request) {
  try {
    return await fetch(request);
  } catch {
    return new Response(
      JSON.stringify({ ok: false, error: "You appear to be offline.", reason: "offline" }),
      { status: 503, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } }
    );
  }
}

/** Development only. The cache is there so the app survives the dev server. */
async function networkFirst(request) {
  try {
    const response = await fetch(request);
    if (isCacheable(response)) await store(SHELL, request, response.clone());
    return response;
  } catch {
    return (await caches.match(request)) ?? offlineResponse();
  }
}

async function cacheFirst(request, cacheName) {
  // ignoreSearch is off: a stylesheet with a query string is a different file.
  const cached = await caches.match(request);
  if (cached) return cached;

  try {
    const response = await fetch(request);
    if (isCacheable(response)) await store(cacheName, request, response.clone());
    return response;
  } catch {
    return offlineResponse();
  }
}

function offlineResponse() {
  return new Response("Offline", { status: 503, headers: { "Content-Type": "text/plain" } });
}

/* -------------------------------------------------------------------------
 * Writing to a cache
 * ---------------------------------------------------------------------- */

function isCacheable(response) {
  if (!response) return false;

  // Opaque cross origin responses are only ever the Google font files, which
  // are immutable and keyed by a URL that changes when they do.
  if (response.type === "opaque") return true;

  if (response.status !== 200) return false;
  if (response.type !== "basic" && response.type !== "default" && response.type !== "cors") return false;
  if (response.redirected) return false;

  const control = (response.headers.get("Cache-Control") ?? "").toLowerCase();
  if (control.includes("no-store") || control.includes("private")) return false;

  const vary = (response.headers.get("Vary") ?? "").toLowerCase();
  if (vary === "*" || vary.includes("cookie")) return false;

  return true;
}

async function store(cacheName, request, response) {
  const cache = await caches.open(cacheName);
  await cache.put(request, response);
}
