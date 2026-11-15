/* GET /api/app-release   the newest release of the Android app, and every one before it

   For the Flutter app's update bar and Updates page, and the 1.0.x Capacitor
   app's update bar (js/app-update.js) and updater. Cached at Vercel's edge, so
   GitHub sees a request every few minutes however many phones ask.

     { version, apk, size, sha256, page, date, notes, history }
     (api/_lib/release.js), or { version: null, history: [] } while there is
     no release with an APK. history is every release, newest first, each
     { version, date, notes, page }.

   ?v=<version> is ignored here, but makes a URL the cache hasn't seen: the
   app adds it when a "new version is out" notification is tapped, so the
   release just published is read now.

   Not wrapped in endpoint() (api/_lib/http.js): it needs no database, and
   its answer is meant to be cached. */

import { allReleases } from "./_lib/release.js";

export default async function handler(req, res) {
  let releases;
  try {
    releases = await allReleases();
  } catch (cause) {
    console.error("[uwuhere] app-release:", cause.message);
    res.setHeader("Cache-Control", "no-store");
    return res.status(502).json({ error: "Couldn't reach GitHub" });
  }

  const history = releases.map(({ version, date, notes, page }) => ({ version, date, notes, page }));
  res.setHeader("Cache-Control", "public, s-maxage=600, stale-while-revalidate=3600");
  // The app's browser build (its Playwright suite) asks from another origin.
  res.setHeader("Access-Control-Allow-Origin", "*");
  return res.status(200).json(releases[0] ? { ...releases[0], history } : { version: null, history });
}
