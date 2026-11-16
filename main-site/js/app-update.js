// The 1.0.x Android app (Capacitor) keeping itself up to date. The app says its
// version (js/app-bridge.js), and /api/app-release the newest one on GitHub;
// a newer one shows in the update bar (js/sw-update.js), whose Update opens
// the app's update window (UpdateActivity.java). That downloads the APK,
// checks it, and hands it to Android's own installer.
//
// Looked up as the page opens, and again on coming back to it after
// UPDATE_CHECK_INTERVAL_MILLISECONDS, as the app can stay open for days. "Not now" lasts this
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

const UPDATE_CHECK_INTERVAL_MILLISECONDS = 60 * 60 * 1000;

let checkedAt = 0;

// "1.10.2" as [1, 10, 2]; any part that is not a number counts as 0.
function versionParts(version) {
  return String(version)
    .split(".")
    .map((part) => {
      const number = parseInt(part, 10);
      if (number) {
        return number;
      }
      return 0;
    });
}

// One part of a version, or 0 past its end.
function partAt(parts, index) {
  const part = parts[index];
  if (part) {
    return part;
  }
  return 0;
}

// Whether candidateVersion comes after currentVersion, number by number:
// 1.10.0 after 1.9.0. The same as newer() in api/_lib/release.js and UpdateActivity.java.
function newer(candidateVersion, currentVersion) {
  const candidateParts = versionParts(candidateVersion);
  const currentParts = versionParts(currentVersion);
  const partCount = Math.max(candidateParts.length, currentParts.length);
  for (let index = 0; index < partCount; index = index + 1) {
    const difference = partAt(candidateParts, index) - partAt(currentParts, index);
    if (difference) {
      return difference > 0;
    }
  }
  return false;
}

// Asks /api/app-release for the newest app, and offers it in the update bar
// when it is newer than the app this page is running in.
async function check() {
  checkedAt = Date.now();
  let latest;
  try {
    const response = await fetch("/api/app-release", { cache: "no-store" });
    if (!response.ok) {
      return;
    }
    latest = await response.json();
  } catch {
    return; // Offline: next time.
  }
  const running = AppBridge.version();
  if (latest === null || latest === undefined || !latest.version) {
    return;
  }
  if (running && newer(latest.version, running)) {
    offerAppUpdate(latest);
  }
}

// In the app: adds the tray's "Check for updates" button when the app can do
// it, looks for a new app now, and again on coming back after an hour.
export function initAppUpdate() {
  if (!AppBridge.native) {
    return;
  }
  AppBridge.ready(5000).then((inApp) => {
    if (!inApp || !AppBridge.has("update")) {
      return;
    }

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
      if (button) {
        hydrateIcons(button);
      }
    }

    check();
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible" && Date.now() - checkedAt > UPDATE_CHECK_INTERVAL_MILLISECONDS) {
        check();
      }
    });
  });
}
