/* The apps' releases on GitHub, tagged android-v<version> with the Android
   APK attached (release/README.md); the desktop installers join them from
   GitHub Actions. Shared by api/app-release.js, which the Android app reads
   (its updater and its Updates page, and the 1.0.x Capacitor app's updater),
   and api/push/release.js, which tells phones a new one is out. */

const RELEASES = "https://api.github.com/repos/augy-studios/uwuHere/releases?per_page=100";
export const TAG = /^android-v(\d+(?:\.\d+)*)$/;

// Whether version a comes after version b, number by number: 1.10.0 after
// 1.9.0. The same as newer() in js/app-update.js and the Flutter app's
// newerVersion() (flutter/lib/features/update/update_bar.dart).
export function newer(a, b) {
  const x = String(a).split(".").map(Number);
  const y = String(b).split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return d > 0;
  }
  return false;
}

/**
 * A release as the app wants it, or null if it isn't one to offer: a draft,
 * a pre-release, a tag that isn't android-v*, or one published before its
 * APK finished uploading.
 *
 *   { version: "1.2.0", apk: "https://github.com/.../uwuhere-1.2.0.apk", size: 712345,
 *     sha256: "ab12…" (GitHub's checksum of the file, or null), page: the release's page,
 *     date: when it was published, notes: its notes, the bold, code and link markup taken out
 *     (headings and bullets kept, for the Updates page to read) }
 *
 * The first five are what the 1.0.x app's updater reads, and keep their meaning.
 */
export function asRelease(rel) {
  const version = TAG.exec(rel?.tag_name || "")?.[1];
  if (!version || rel.draft || rel.prerelease) return null;
  const assets = rel.assets || [];
  const apk = assets.find((a) => a.name === `uwuhere-${version}.apk`) || assets.find((a) => /\.apk$/i.test(a.name));
  if (!apk || apk.state !== "uploaded") return null;
  return {
    version,
    apk: apk.browser_download_url,
    size: apk.size,
    sha256: /^sha256:[0-9a-f]{64}$/i.test(apk.digest || "") ? apk.digest.slice(7).toLowerCase() : null,
    page: rel.html_url,
    date: rel.published_at ?? null,
    notes: plain(rel.body),
  };
}

function plain(body) {
  return String(body ?? "")
    .replace(/\r\n/g, "\n")
    .replace(/\*\*(.+?)\*\*/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .trim();
}

/**
 * Every release worth offering, newest first. GitHub allows 60 requests an
 * hour per IP without a token; GITHUB_TOKEN (any token, no scopes needed for
 * a public repository) raises that to 5,000, and is optional.
 */
export async function allReleases() {
  const headers = { accept: "application/vnd.github+json", "x-github-api-version": "2022-11-28", "user-agent": "uwuHere" };
  if (process.env.GITHUB_TOKEN) headers.authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  const r = await fetch(RELEASES, { headers, signal: AbortSignal.timeout(10_000) });
  if (!r.ok) throw new Error(`GitHub replied ${r.status}`);
  const releases = await r.json();
  return (Array.isArray(releases) ? releases : [])
    .map(asRelease)
    .filter(Boolean)
    .sort((a, b) => (newer(a.version, b.version) ? -1 : newer(b.version, a.version) ? 1 : 0));
}

/** The newest release to offer, or null while there is none. */
export async function latestRelease() {
  return (await allReleases())[0] ?? null;
}
