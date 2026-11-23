// The Flutter build (flutter/build/web) on 47481, for the suite. No dependencies.
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const root = resolve(here, "../build/web");
const CONTENT_TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".wasm": "application/wasm", ".png": "image/png", ".ico": "image/x-icon",
  ".ttf": "font/ttf", ".otf": "font/otf", ".woff2": "font/woff2", ".svg": "image/svg+xml", ".bin": "application/octet-stream",
};

// Answers each request with the file under the build folder, refusing any path that climbs out
// of it, and a folder's index.html for a folder.
createServer(async (request, response) => {
  const path = normalize(decodeURIComponent(new URL(request.url, "http://x").pathname)).replace(/^[/\\]+/, "");
  let file = resolve(root, path);
  if (!file.startsWith(root)) {
    response.writeHead(403).end();
    return;
  }
  try {
    if ((await stat(file)).isDirectory()) {
      file = join(file, "index.html");
    }
    const body = await readFile(file);
    let contentType = CONTENT_TYPES[extname(file)];
    if (!contentType) {
      contentType = "application/octet-stream";
    }
    response.writeHead(200, { "content-type": contentType, "cache-control": "no-store" });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
}).listen(47481, "127.0.0.1", () => {
  console.log(`${root} on 47481`);
});
