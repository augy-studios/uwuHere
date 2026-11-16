// The website (main-site/) on 47482, as Vercel serves it: clean addresses (/host is host.html).
// Its /api is answered by the tests themselves (tests/site.spec.js routes it), and 404s here.
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const root = resolve(here, "../../main-site");
const CONTENT_TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".png": "image/png", ".ico": "image/x-icon", ".svg": "image/svg+xml",
};

// Answers one request as Vercel would: /api/ gets a JSON 404, a path without an extension is its
// .html page, a folder is its index.html, and any path that climbs out of main-site/ is refused.
const handler = async (request, response) => {
  let url;
  try {
    url = new URL(request.url, "http://x");
  } catch {
    response.writeHead(400);
    return response.end();
  }
  if (url.pathname.startsWith("/api/")) {
    response.writeHead(404, { "content-type": "application/json" });
    return response.end(JSON.stringify({ ok: false, error: "Not found", reason: "not-found" }));
  }
  let path = normalize(decodeURIComponent(url.pathname)).replace(/^[/\\]+/, "");
  if (path === "") {
    path = "index.html";
  }
  let file = resolve(root, path);
  if (!file.startsWith(root)) {
    response.writeHead(403).end();
    return;
  }
  try {
    if (!extname(file)) {
      file = file + ".html";
    }
    if ((await stat(file)).isDirectory()) {
      file = join(file, "index.html");
    }
    // As Vercel sends them: no-store would keep the service worker from caching anything.
    let contentType = CONTENT_TYPES[extname(file)];
    if (!contentType) {
      contentType = "application/octet-stream";
    }
    response.writeHead(200, {
      "content-type": contentType,
      "cache-control": "public, max-age=0, must-revalidate",
    });
    response.end(await readFile(file));
  } catch {
    response.writeHead(404).end();
  }
};

// 127.0.0.1, and 127.0.0.2 for tests/site-sw.spec.js: the browser trusts both as it does a site
// on https, but the service worker counts only 127.0.0.1 as development.
createServer(handler).listen(47482, "127.0.0.1", () => {
  console.log(`${root} on 47482`);
});
createServer(handler).listen(47482, "127.0.0.2");
