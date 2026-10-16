// Notifications, in the Android app only. The bell in the Edge Tray opens a
// window with three switches, and each is a set of FCM topics the app joins
// (HerePlugin.setTopic), so the server keeps no list of phones:
//
//   checkins  "Alex checked in", "Sam left early", for location check-ins and
//             early leavers at events this phone hosts. One topic per event,
//             named from its host key (hostTopic below), so only a phone that
//             holds the key can name it. api/checkin.js and api/leave.js send
//             to it through api/_lib/alerts.js. Same-wifi check-ins need the
//             host page open anyway, so they don't notify.
//   releases  a new version of the app, pushed by api/push/release.js when a
//             release is published on GitHub
//   news      sent by hand from the Firebase console (android/FIREBASE-SETUP.md)
//
// The host page names its event with watchHostAlerts() whenever it opens,
// and takes it off when the event ends; the app joins the topic while
// "checkins" is on.
//
// Turning a switch on asks Android's notification permission first (Android
// 13 and later), through Capacitor's PushNotifications plugin. Nothing is
// asked until a switch is turned on.
//
// The bell only shows when the app was built with Firebase
// (google-services.json). The website and the PWA have no notifications.

import { AppBridge } from "./app-bridge.js";
import { addTrayButton } from "./tray.js";
import { hydrateIcons, openModal, closeModal } from "./ui.js";

const NOTES = {
  denied: "Notifications are off for uwuHere in Android's settings. Turn them on there, then come back.",
  offline: "Couldn't reach Firebase. Check you're online, then try again.",
};

const SWITCHES = [
  { topic: "checkins", label: "Check-ins to my events", hint: "Who checks in by location or leaves early, at events this phone hosts" },
  { topic: "releases", label: "New versions of the app", hint: "When an update is ready to install" },
  { topic: "news", label: "News from uwuHere", hint: "Now and then: new features, and other news" },
];

const $ = (id) => document.getElementById(id);
let switches = [];

function buildModal() {
  const modal = document.createElement("div");
  modal.className = "modal-backdrop hidden";
  modal.id = "notifyModal";
  modal.innerHTML = `
    <div class="modal glass" role="dialog" aria-modal="true" aria-labelledby="notifyModalTitle">
      <div class="modal-head">
        <h2 id="notifyModalTitle">Notifications</h2>
        <button class="icon-btn small" type="button" data-close-modal="notifyModal" aria-label="Close">
          <span data-icon="close"></span>
        </button>
      </div>
      <div class="stack">
        ${SWITCHES.map(
          (s) => `
          <label class="toggle-row">
            <span class="toggle-row-text">${s.label}<small>${s.hint}</small></span>
            <input class="switch" type="checkbox" role="switch" data-topic="${s.topic}">
          </label>`
        ).join("")}
      </div>
      <p class="mode-note" id="notifyNote" hidden></p>
      <button class="btn btn-block" id="notifySettingsBtn" type="button" hidden>Open Android's settings</button>
    </div>`;
  document.body.append(modal);
  hydrateIcons(modal);

  // shell.js wires the modals that ship in the page; this one is made later.
  modal.querySelector("[data-close-modal]").addEventListener("click", () => closeModal("notifyModal"));
  modal.addEventListener("click", (e) => {
    if (e.target === modal) closeModal("notifyModal");
  });
  return modal;
}

function note(text, { settings = false } = {}) {
  const p = $("notifyNote");
  p.textContent = text || "";
  p.hidden = !text;
  $("notifySettingsBtn").hidden = !settings;
}

async function allowed() {
  const now = await AppBridge.call("PushNotifications", "checkPermissions");
  if (now.receive === "granted") return true;
  // Once refused for good, Android won't prompt again: its settings are the
  // only way.
  if (now.receive === "denied") return false;
  const after = await AppBridge.call("PushNotifications", "requestPermissions");
  return after.receive === "granted";
}

async function refresh() {
  note("");
  try {
    const [topics, permission] = await Promise.all([
      AppBridge.call("Here", "topics"),
      AppBridge.call("PushNotifications", "checkPermissions"),
    ]);
    switches.forEach((input) => {
      input.checked = Boolean(topics[input.dataset.topic]);
    });
    // Turned on here, then switched off in Android's settings: say why
    // nothing arrives.
    const anyOn = SWITCHES.some((s) => topics[s.topic]);
    if (anyOn && permission.receive !== "granted") note(NOTES.denied, { settings: true });
  } catch {
    // The switches stay as drawn.
  }
}

async function toggle(input) {
  const on = input.checked;
  input.disabled = true;
  note("");
  try {
    if (on && !(await allowed())) {
      input.checked = false;
      note(NOTES.denied, { settings: true });
      return;
    }
    await AppBridge.call("Here", "setTopic", { topic: input.dataset.topic, on });
  } catch (cause) {
    input.checked = !on;
    note(cause?.message || NOTES.offline);
  } finally {
    input.disabled = false;
  }
}

export function initAppNotify() {
  if (!AppBridge.native) return;
  AppBridge.ready(5000).then((inApp) => {
    if (!inApp || !AppBridge.has("push")) return;

    const modal = buildModal();
    switches = [...modal.querySelectorAll("[data-topic]")];
    switches.forEach((input) => input.addEventListener("change", () => toggle(input)));

    const bell = addTrayButton({
      id: "notifyBtn",
      icon: "bell",
      label: "Notifications",
      onClick: () => {
        refresh();
        openModal("notifyModal");
      },
    });
    if (bell) {
      bell.setAttribute("aria-haspopup", "dialog");
      hydrateIcons(bell);
    }

    $("notifySettingsBtn").addEventListener("click", () => {
      AppBridge.call("Here", "openSettings", { what: "notifications" }).catch(() => {});
    });
    // Back from Android's settings with the window still open.
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible" && !modal.classList.contains("hidden")) refresh();
    });
  });
}

/* -------------------------------------------------------------------------
 * Host alerts: an event's own topic
 * ---------------------------------------------------------------------- */

// uwuhere-host- and the first 40 hex digits of the SHA-256 of the event's
// host key. api/_lib/alerts.js works out the same from the event id, and
// HerePlugin.watchEvent accepts nothing else.
async function hostTopic(hostKey) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(hostKey));
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `uwuhere-host-${hex.slice(0, 40)}`;
}

// What this page view has already told the app, so a host page polling every
// few seconds asks once.
const told = new Map();

/**
 * This phone hosts the event with this key (on), or no longer does (off): an
 * ended event, or a key that stopped working. Quietly nothing outside the
 * app, or in an app built without Firebase.
 */
export async function watchHostAlerts(hostKey, on) {
  if (!AppBridge.native || !hostKey || told.get(hostKey) === on) return;
  told.set(hostKey, on);
  if (!(await AppBridge.ready(5000)) || !AppBridge.has("push")) return;
  try {
    const topic = await hostTopic(hostKey);
    await AppBridge.call("Here", "watchEvent", { topic, on });
  } catch {
    // Asked again the next time the host page opens.
    told.delete(hostKey);
  }
}
