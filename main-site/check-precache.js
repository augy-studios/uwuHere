// Checks sw.js's PRECACHE list against what is actually on disk.
//
//   node check-precache.js      (or: npm run check)
//
// A hand-written list drifts two ways and neither announces itself:
//
//   an entry with no file    the install logs a warning nobody reads, and one
//                            page or module is quietly missing offline
//   a file with no entry     it works online and vanishes offline
//
// It also fails if the worker calls skipWaiting() or clients.claim() anywhere
// but its message handler, which would silently undo the update bar
// (update-bar-spec.md, "Checking it works").

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));

// Addresses the worker precaches that are not a file of the same name.
// cleanUrls serves each from the .html file beside it, and 308s the .html
// spelling to the clean one, which is why the clean one is what is cached.
const ALIASES = new Map([
  ["/", "index.html"],
  ["/host", "host.html"],
  ["/join", "join.html"],
]);

const REDIRECTING = new Set(["/index.html", "/host.html", "/join.html"]);

// Shipped files that are deliberately not precached, with the reason.
const DELIBERATELY_ABSENT = new Map([
  ["/sw.js", "The worker itself. Caching it is how a worker becomes unreplaceable."],
  ["/HAT-main.png", "The og:image. Only a crawler ever fetches it."],
  ["/vercel.json", "Build configuration. The browser never asks for it."],
  ["/package.json", "Dependencies for the functions under api/. Not part of the page."],
  ["/package-lock.json", "As above."],
  ["/browserconfig.xml", "Old Windows tile metadata, fetched by nothing the app runs."],
  ["/robots.txt", "For crawlers, which are never offline."],
  ["/check-precache.js", "This checker. Not part of the site."],
  ["/404.html", "Left as it was. An unknown address offline gets the home page instead."],
  ["/404.css", "As above."],
]);

const SKIP_DIRS = new Set(["node_modules", ".git", ".well-known", "images", "api"]);
const CACHEABLE = /\.(html|css|js|mjs|json|png|ico|svg|woff2?|xml|txt)$/;

const source = readFileSync(join(root, "sw.js"), "utf8");

function readPrecache() {
  const block = source.match(/const PRECACHE = \[([\s\S]*?)\n\];/);
  if (!block) {
    console.error("check-precache: could not find the PRECACHE list in sw.js.");
    process.exit(1);
  }
  const withoutComments = block[1].replace(/\/\/.*$/gm, "");
  return [...withoutComments.matchAll(/"([^"]+)"/g)].map((m) => m[1]);
}

function walk(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name) || entry.name.startsWith(".")) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else out.push("/" + relative(root, full).split(sep).join("/"));
  }
  return out;
}

const precache = readPrecache();
const onDisk = walk(root).filter((path) => CACHEABLE.test(path));
const problems = [];

for (const entry of precache) {
  if (REDIRECTING.has(entry)) {
    problems.push(`precached address redirects: ${entry}. Precache the clean address instead.`);
    continue;
  }
  const file = ALIASES.get(entry) ?? entry.replace(/^\//, "");
  if (!existsSync(join(root, file))) problems.push(`precached but not on disk: ${entry}`);
}

const precached = new Set();
for (const entry of precache) {
  precached.add(entry);
  const alias = ALIASES.get(entry);
  if (alias) precached.add("/" + alias);
}
for (const file of onDisk) {
  if (precached.has(file) || DELIBERATELY_ABSENT.has(file)) continue;
  problems.push(
    `on disk but not precached: ${file}\n` +
    `      Add it to PRECACHE in sw.js, or to DELIBERATELY_ABSENT here with the reason.`
  );
}

const seen = new Set();
for (const entry of precache) {
  if (seen.has(entry)) problems.push(`listed twice in PRECACHE: ${entry}`);
  seen.add(entry);
}

// skipWaiting and clients.claim belong to the message handler and nowhere
// else. Comments are stripped first, since they mention both by name.
const code = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
const handler = code.match(/addEventListener\("message"[\s\S]*?\n\}\);/)?.[0] ?? "";
const outside = code.replace(handler, "");
if (/skipWaiting\s*\(|clients\.claim\s*\(/.test(outside)) {
  problems.push("sw.js calls skipWaiting() or clients.claim() outside its message handler.");
}

if (problems.length > 0) {
  console.error("check-precache found problems:\n");
  for (const problem of problems) console.error("  - " + problem);
  console.error("");
  process.exit(1);
}

console.log(`check-precache: ${precache.length} entries, all present, every shipped file accounted for.`);
