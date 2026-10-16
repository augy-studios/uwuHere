/* GET /api/app-release   the newest release of the Android app (android/)

   For its update bar (js/app-update.js) and its own updater
   (UpdateActivity.java). Cached at Vercel's edge, so GitHub sees a request
   every few minutes however many phones ask.

     { version, apk, size, sha256, page } (api/_lib/release.js), or
     { version: null } while there is no release with an APK.

   ?v=<version> is ignored here, but makes a URL the cache hasn't seen: the
   app adds it when a "new version is out" notification is tapped, so the
   release just published is read now.

   Not wrapped in endpoint() (api/_lib/http.js): it needs no database, and
   its answer is meant to be cached. */

import { latestRelease } from "./_lib/release.js";

export default async function handler(req, res) {
  let best;
  try {
    best = await latestRelease();
  } catch (cause) {
    console.error("[uwuhere] app-release:", cause.message);
    res.setHeader("Cache-Control", "no-store");
    return res.status(502).json({ error: "Couldn't reach GitHub" });
  }

  res.setHeader("Cache-Control", "public, s-maxage=600, stale-while-revalidate=3600");
  return res.status(200).json(best || { version: null });
}
