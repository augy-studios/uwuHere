// The Android app (android/) keeping itself up to date. The app says its
// version (js/app-bridge.js), and /api/app-release the newest one on GitHub;
// a newer one shows in the update bar (js/sw-update.js), whose Update opens
// the app's update window (UpdateActivity.java). That downloads the APK,
// checks it, and hands it to Android's own installer.
//
// Looked up as the page opens, and again on coming back to it after
// UPDATE_CHECK_MS, as the app can stay open for days. "Not now" lasts this
// page view only, as for the site's own update.
//
// The Edge Tray's "Check for updates" button looks whenever you like: it asks
// for a new site version too, and opens the update window, which says if you
// have the newest app and asks before downloading one.
//
// Nothing here runs in a browser or the PWA.

import { AppBridge } from "./app-bridge.js";
import { offerAppUpdate, checkSiteUpdate } from "./sw-update.js";
import { addTrayButton } from "./tray.js";
import { hydrateIcons } from "./ui.js";

const UPDATE_CHECK_MS = 60 * 60 * 1000;

let checkedAt = 0;

// Whether version a comes after version b, number by number: 1.10.0 after
// 1.9.0. The same as newer() in api/_lib/release.js and UpdateActivity.java.
function newer(a, b) {
  const x = String(a).split(".").map((n) => parseInt(n, 10) || 0);
  const y = String(b).split(".").map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return d > 0;
  }
  return false;
}

async function check() {
  checkedAt = Date.now();
  let latest;
  try {
    const response = await fetch("/api/app-release", { cache: "no-store" });
    if (!response.ok) return;
    latest = await response.json();
  } catch {
    return; // Offline: next time.
  }
  const running = AppBridge.version();
  if (latest?.version && running && newer(latest.version, running)) offerAppUpdate(latest);
}

export function initAppUpdate() {
  if (!AppBridge.native) return;
  AppBridge.ready(5000).then((inApp) => {
    if (!inApp || !AppBridge.has("update")) return;

    if (AppBridge.has("checkupdate")) {
      const button = addTrayButton({
        id: "appUpdateBtn",
        icon: "appUpdate",
        label: "Check for updates",
        onClick: () => {
          checkSiteUpdate();
          AppBridge.call("Here", "update", { check: true }).catch(() => {});
        },
      });
      if (button) hydrateIcons(button);
    }

    check();
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible" && Date.now() - checkedAt > UPDATE_CHECK_MS) check();
    });
  });
}
