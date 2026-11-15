// The Flutter build (flutter/build/web) on 47481, for the suite. No dependencies.
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const root = resolve(here, "../build/web");
const TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".wasm": "application/wasm", ".png": "image/png", ".ico": "image/x-icon",
  ".ttf": "font/ttf", ".otf": "font/otf", ".woff2": "font/woff2", ".svg": "image/svg+xml", ".bin": "application/octet-stream",
};

createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname)).replace(/^[/\\]+/, "");
  let file = resolve(root, path);
  if (!file.startsWith(root)) return void res.writeHead(403).end();
  try {
    if ((await stat(file)).isDirectory()) file = join(file, "index.html");
    const body = await readFile(file);
    res.writeHead(200, { "content-type": TYPES[extname(file)] || "application/octet-stream", "cache-control": "no-store" });
    res.end(body);
  } catch {
    res.writeHead(404).end();
  }
}).listen(47481, "127.0.0.1", () => console.log(`${root} on 47481`));
