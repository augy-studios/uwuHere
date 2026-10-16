// The update prompt bar (update-bar-spec.md). A new worker never activates on
// its own: it downloads, installs, and waits, and the only thing that
// promotes it is a person pressing Reload.

import { escapeHtml } from "./ui.js";
import { trackBanner } from "./tray.js";

const SW_URL = "/sw.js";

const COPY = {
  label: "Update",
  ready: "A new version of uwuHere is ready.",
  reload: "Reload",
  later: "Not now",
};

let registration = null;
let waitingWorker = null;
let reloading = false;
let dismissed = false;

function render() {
  const existing = document.querySelector(".update-notice");

  if (!waitingWorker || dismissed) {
    existing?.remove();
    trackBanner(null);
    return;
  }

  const bar = existing ?? document.createElement("div");
  bar.className = "update-notice";
  bar.setAttribute("role", "status");
  bar.setAttribute("aria-label", COPY.label);
  bar.innerHTML = `
    <div class="update-notice-inner">
      <p>${escapeHtml(COPY.ready)}</p>
      <button type="button" class="btn btn-primary" data-sw-update>
        ${escapeHtml(COPY.reload)}
      </button>
      <button type="button" class="btn btn-quiet" data-sw-later>
        ${escapeHtml(COPY.later)}
      </button>
    </div>
  `;

  bar.querySelector("[data-sw-update]").addEventListener("click", () => {
    // The only place anything asks for skipWaiting. The reload happens on
    // controllerchange, not here.
    waitingWorker?.postMessage("skip-waiting");
  });

  bar.querySelector("[data-sw-later]").addEventListener("click", () => {
    // This page view only. Persisting it would mean somebody who dismisses
    // once never hears about an update again.
    dismissed = true;
    render();
  });

  if (!existing) {
    document.body.prepend(bar);
    trackBanner(bar);
  }
}

function watchForUpdate() {
  if (!registration) return;

  // A worker already waiting when the page opened. This is the ordinary case
  // on the second page view after a deploy, and without it the prompt would
  // only ever reach somebody who happened to have the page open at the
  // moment the new worker finished installing.
  if (registration.waiting && navigator.serviceWorker.controller) {
    waitingWorker = registration.waiting;
    render();
  }

  registration.addEventListener("updatefound", () => {
    const installing = registration.installing;
    if (!installing) return;

    installing.addEventListener("statechange", () => {
      // `installed` with a controller present means an update. `installed`
      // with no controller is a first install, which has nothing to prompt
      // about: there is no previous version on screen to protect.
      if (installing.state === "installed" && navigator.serviceWorker.controller) {
        waitingWorker = registration.waiting ?? installing;
        render();
      }
    });
  });
}

// The browser only re-fetches the worker script on its own schedule, which
// can be hours. Asking explicitly is what turns "a new version is on the
// server" into "the bar is on screen": on returning to the tab, and on a slow
// interval for a host page left open all day.
const UPDATE_INTERVAL_MS = 30 * 60 * 1000;

function checkForUpdate() {
  if (!registration || !navigator.onLine || document.visibilityState !== "visible") return;
  registration.update().catch(() => {
    // A failed check is not worth reporting: the next one will do.
  });
}

function watchForNewDeploys() {
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") checkForUpdate();
  });
  window.addEventListener("online", checkForUpdate);
  setInterval(checkForUpdate, UPDATE_INTERVAL_MS);
}

function registerWorker() {
  if (!("serviceWorker" in navigator)) return;

  navigator.serviceWorker
    .register(SW_URL)
    .then((reg) => {
      registration = reg;
      watchForUpdate();
      watchForNewDeploys();
    })
    .catch((cause) => {
      // A refused registration is not a reason to break the page. Private
      // browsing in some browsers, and any http origin that is not
      // localhost, land here.
      console.warn("service worker registration failed:", cause);
    });

  // The swap, once somebody has accepted it. Reloading here rather than in
  // the click handler is what makes the page come back on the new version:
  // the controller has changed by this point, so the reload is served by the
  // new worker and not the one being replaced.
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (reloading) return;
    reloading = true;
    window.location.reload();
  });
}

export function initUpdateBar() {
  // Registration on `load`, not immediately: installing fetches everything
  // the worker precaches, and starting that while the page is still fetching
  // its own assets is how a service worker makes a first visit slower for no
  // gain.
  if (document.readyState === "complete") registerWorker();
  else window.addEventListener("load", registerWorker, { once: true });
}
