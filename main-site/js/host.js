// The host page: /host?id=CODE
//
// Shows the code and QR, takes same-wifi check-ins over P2P while it is
// open, and keeps the list. The server is the source of truth; this page
// polls it, and keeps its last copy in storage so the list still opens with
// no connection.
//
// A P2P check-in that arrives while the server cannot be reached is not lost:
// it goes into an outbox on this device, the attendee is told they are in,
// and the outbox is sent when the connection comes back. People added by
// hand while offline go the same way.
//
// In the Android app (js/app-bridge.js) a few things go through the app
// instead: the screen kept on (the WebView has no Screen Wake Lock), the big
// QR code at full brightness, the CSV saved to Downloads (the WebView cannot
// download a file the page made), this event's check-in notifications
// (js/app-notify.js), and the home screen widget (js/app-widget.js). Tapping
// phones only works there: the app makes this phone an NFC tag that hands each
// phone touching it a one-time link (TapService.java, api/_lib/tap.js). So
// does checking in with no internet:
// the app makes this phone a wifi hotspot serving a check-in page of its own
// (Hotspot.java), and its check-ins come here to be recorded like same-wifi
// ones. And so does Bluetooth: attendees who have the app check in phone to
// phone over Nearby Connections (Mesh.java), recorded here the same way.

import { bootShell } from "./shell.js";
import { postJson } from "./api.js";
import { AppBridge } from "./app-bridge.js";
import { watchHostAlerts } from "./app-notify.js";
import { tellWidget, forgetWidget } from "./app-widget.js";
import { Host, normaliseCode, isValidCode, PROTOCOL_VERSION } from "./p2p.js";
import { qrToSvg } from "./qr.js";
import { getPosition } from "./geo.js";
import { checkPassword, renderPasswordChecks } from "./password.js";
import * as store from "./store.js";
import {
  escapeHtml, formatTime, formatDateTime, hydrateIcons, openModal, closeModal, toast, charCount,
  paintHereButton, armed,
} from "./ui.js";

bootShell();

const $ = (id) => document.getElementById(id);
const code = normaliseCode(new URLSearchParams(location.search).get("id"));

const POLL_MS = 5000;
const TAKEN_RETRIES = 3;
const TAKEN_RETRY_MS = 4000;
const LIMITS = { title: 80, buttonLabel: 20, noteLabel: 40, name: 60, note: 120 };

let hostKey = null;
let event = null; // the host view of the event, from the server or the cache
let attendees = []; // from the server
let savedAt = null; // when the copy above last came from the server
let connection = "ok"; // "ok" | "offline" | "unavailable"
let pollTimer = null;
let flushing = false;
let lastListKey = "";

let host = null;
let p2p = { status: "idle", message: "" };
let takenRetries = 0;
let retryTimer = null;
let wakeLock = null;

// What the app last said about tapping phones: "idle", "ready", "nfc-off",
// "unsupported" or "error".
let tapState = "idle";
let tapWanted = false;
// What the app last said about Bluetooth check-in (Mesh.java): "idle",
// "ready", "needs-permission", "denied", "bt-off", "unsupported" or "failed".
let btState = "idle";
let btWanted = false;

// Whether the app has said what it can do yet (AppBridge.ready, at boot).
let bridgeHeard = !AppBridge.native;

/* -------------------------------------------------------------------------
 * Views
 * ---------------------------------------------------------------------- */

function show(view) {
  for (const id of ["missingView", "lockedView", "hostView"]) $(id).hidden = id !== view;
  const hosting = view === "hostView" && event;
  $("qrTrayBtn").hidden = !hosting || event.ended;
  $("settingsBtn").hidden = !hosting || event.ended;
  $("csvTrayBtn").hidden = !hosting;
  if (!hosting || event.ended) closeIfOpen("qrModal");
}

function closeIfOpen(id) {
  if (!$(id).classList.contains("hidden")) closeModal(id);
}

function showMissing(title, text) {
  $("missingTitle").textContent = title;
  $("missingText").textContent = text;
  show("missingView");
}

function showLocked(message) {
  $("lockedText").textContent = message || "Enter the password set when this event was made.";
  show("lockedView");
}

/* -------------------------------------------------------------------------
 * Talking to the server
 * ---------------------------------------------------------------------- */

function setConnection(state) {
  connection = state;
  renderSync();
}

// Why a request did not reach a usable answer, if that is what happened.
function connectionFailure(result) {
  if (result.offline) return "offline";
  if (result.status >= 500) return "unavailable";
  return null;
}

function applySnapshot(snapshot, { fromCache = false } = {}) {
  event = snapshot.event;
  attendees = Array.isArray(snapshot.attendees) ? snapshot.attendees : [];
  savedAt = fromCache ? snapshot.savedAt : new Date().toISOString();
  if (!fromCache) {
    store.saveHostCache(code, { event, attendees });
    store.saveHosted(code, hostKey, event);
    // Check-ins by location reach this phone while the app is closed, until
    // the event ends.
    watchHostAlerts(hostKey, !event.ended);
    // The app's home screen widget, which carries on from here by itself.
    tellWidget(code, hostKey, event, attendees);
  }
  render();
  syncP2p();
  syncTap();
  syncBluetooth();
}

function persist() {
  store.saveHostCache(code, { event, attendees });
}

function upsertAttendee(attendee) {
  const i = attendees.findIndex((a) => a.id === attendee.id);
  if (i === -1) attendees.push(attendee);
  else attendees[i] = attendee;
  persist();
}

function loseAccess() {
  watchHostAlerts(hostKey, false);
  forgetWidget(code);
  hostKey = null;
  store.forgetHosted(code);
  stopP2p();
  syncTap();
  syncBluetooth();
  showLocked("This browser can no longer manage this event. Enter its password to open it.");
}

function eventGone() {
  watchHostAlerts(hostKey, false);
  forgetWidget(code);
  store.forgetHosted(code);
  stopP2p();
  event = null;
  syncTap();
  syncBluetooth();
  showMissing(
    "This event is gone",
    `Events are deleted ${store.PURGE_AFTER_END_DAYS} days after they end, or ${store.PURGE_UNENDED_DAYS} days after they were made if nobody ends them.`
  );
}

async function refresh() {
  if (!hostKey) return;
  await flushOutbox();

  const result = await postJson("host", { code, hostKey, action: "get" });
  if (result.ok) {
    setConnection("ok");
    applySnapshot(result.data);
    return;
  }

  const failure = connectionFailure(result);
  if (failure) return setConnection(failure);
  if (result.reason === "not-host") return loseAccess();
  if (result.reason === "not-found") return eventGone();
}

/** A host action that answers with the whole snapshot. */
async function mutate(action, extra, offlineMessage) {
  const result = await postJson("host", { code, hostKey, action, ...extra });
  if (result.ok) {
    setConnection("ok");
    applySnapshot(result.data);
    return { ok: true };
  }

  const failure = connectionFailure(result);
  if (failure) {
    setConnection(failure);
    return { ok: false, error: failure === "offline" ? offlineMessage : result.error };
  }
  if (result.reason === "not-host") {
    loseAccess();
    return { ok: false, error: result.error };
  }
  if (result.reason === "ended") {
    await refresh();
    return { ok: false, error: "This event has already ended." };
  }
  return { ok: false, error: result.error };
}

/* ---- the outbox: check-ins taken while the server was out of reach ---- */

function queue(kind, payload) {
  const items = store.getOutbox(code);
  items.push({ localId: `local-${crypto.randomUUID()}`, kind, payload });
  store.saveOutbox(code, items);
  render();
}

async function flushOutbox() {
  if (flushing || !hostKey) return;
  flushing = true;

  try {
    let items = store.getOutbox(code);
    while (items.length > 0) {
      const item = items[0];
      const result = await postJson("host", { code, hostKey, action: item.kind, ...item.payload });

      // Still unreachable, or this browser lost its key: keep everything for
      // the next attempt rather than dropping somebody's check-in.
      if (!result.ok && (connectionFailure(result) || result.reason === "not-host")) break;

      if (result.ok) upsertAttendee(result.data.attendee);
      else if (result.reason !== "ended") toast(`Could not save ${item.payload.name}: ${result.error}`);

      items = store.getOutbox(code).filter((i) => i.localId !== item.localId);
      store.saveOutbox(code, items);
    }
  } finally {
    flushing = false;
    render();
  }
}

/* -------------------------------------------------------------------------
 * Rendering
 * ---------------------------------------------------------------------- */

const METHOD = {
  p2p: { icon: "wifi", label: "Same wifi" },
  location: { icon: "pin", label: "Location" },
  manual: { icon: "hand", label: "Added by hand" },
  tap: { icon: "tap", label: "Tapped phones" },
  tap_late: { icon: "tap", label: "Tapped, sent later" },
  mesh: { icon: "bluetooth", label: "Bluetooth" },
  hotspot: { icon: "hotspot", label: "Host's hotspot" },
};

function joinLink() {
  return `${location.origin}/join?id=${code}`;
}

function displayList() {
  const pending = store.getOutbox(code).map((item) => ({
    id: item.localId,
    name: item.payload.name,
    note: item.payload.note,
    method: item.kind === "record" ? item.payload.method || "p2p" : "manual",
    distance: null,
    checkedInAt: item.payload.at,
    leftEarlyAt: null,
    pending: true,
  }));
  return [...attendees, ...pending].sort((a, b) => String(b.checkedInAt).localeCompare(String(a.checkedInAt)));
}

function render() {
  if (!event) return;
  show("hostView");

  const ended = event.ended;
  document.title = `${event.title || code} | uwuHere`;
  $("eventTitle").textContent = event.title || "Untitled event";

  const link = joinLink();
  $("codeBtn").textContent = code;
  $("shareLink").textContent = link;
  if ($("qrHolder").dataset.link !== link) {
    $("qrHolder").innerHTML = qrToSvg(link);
    $("qrHolder").dataset.link = link;
  }

  $("endedBanner").hidden = !ended;
  if (ended) {
    const purge = new Date(Date.parse(event.endedAt) + store.PURGE_AFTER_END_DAYS * 86400000).toISOString();
    $("endedBanner").textContent =
      `Ended ${formatDateTime(event.endedAt)}. The list can be downloaded here until ` +
      `${formatDateTime(purge)}, then it is deleted.`;
  }

  $("shareBlock").hidden = ended;
  if (ended) stopHotspot();
  $("pauseBtn").hidden = ended;
  $("endBtn").hidden = ended;
  $("addForm").hidden = ended;
  $("pausedBanner").hidden = ended || !event.paused;

  $("pauseBtn").innerHTML = event.paused
    ? `<span data-icon="play"></span>Resume`
    : `<span data-icon="pause"></span>Pause`;
  hydrateIcons($("pauseBtn"));

  $("locRow").hidden = !event.allowLocation || ended;
  $("locText").textContent = event.hasLocation
    ? `Location check-in within ${event.radius} m of this event's spot.`
    : "Location check-in is on, but no spot is set. Set one in Event settings.";

  $("addNote").hidden = !event.noteLabel;
  $("addNote").placeholder = event.noteLabel || "";
  $("addNote").setAttribute("aria-label", event.noteLabel || "Note");

  renderList();
  renderSync();
  renderP2p();
  renderTap();
  renderBluetooth();
  renderHotspot();
}

function renderList() {
  const list = displayList();
  const key = JSON.stringify([list, event.ended, event.noteLabel]);
  if (key === lastListKey) return;
  lastListKey = key;

  const left = list.filter((a) => a.leftEarlyAt).length;
  $("listCount").textContent =
    list.length === 0 ? "" : `${list.length} checked in${left ? `, ${left} left early` : ""}`;
  $("emptyList").hidden = list.length > 0;

  $("attendeeList").innerHTML = list
    .map((a) => {
      const method = METHOD[a.method] ?? METHOD.manual;
      const how = a.distance === null || a.distance === undefined ? method.label : `${method.label}, ${a.distance} m away`;
      const note = a.note
        ? `<span class="attendee-note">${escapeHtml(event.noteLabel ? `${event.noteLabel}: ` : "")}${escapeHtml(a.note)}</span>`
        : "";
      const remove = event.ended
        ? ""
        : `<button class="icon-btn small remove-btn" type="button" data-remove="${escapeHtml(a.id)}"
             ${a.pending ? 'data-pending="1"' : ""} aria-label="Remove ${escapeHtml(a.name)}" title="Remove">
             <span data-icon="trash"></span>
           </button>`;

      return `
        <li class="attendee">
          <span class="attendee-main">
            <span class="attendee-name">${escapeHtml(a.name)}</span>
            ${note}
          </span>
          <span class="attendee-meta">
            <span class="chip" title="${escapeHtml(how)}"><span data-icon="${method.icon}"></span>${formatTime(a.checkedInAt)}<span class="visually-hidden">, ${escapeHtml(how)}</span></span>
            ${a.leftEarlyAt ? `<span class="chip warn"><span data-icon="door"></span>Left ${formatTime(a.leftEarlyAt)}</span>` : ""}
            ${a.pending ? `<span class="chip busy">Not sent yet</span>` : ""}
          </span>
          ${remove}
        </li>`;
    })
    .join("");
  hydrateIcons($("attendeeList"));
}

function renderSync() {
  const banner = $("syncBanner");
  const pending = store.getOutbox(code).length;
  const waiting = pending
    ? ` ${pending} check-in${pending === 1 ? "" : "s"} saved on this device will be sent when the connection is back.`
    : "";

  if (connection === "offline") {
    banner.className = "banner warn";
    banner.textContent = `Offline. Showing the list from ${formatTime(savedAt)}.${waiting}`;
  } else if (connection === "unavailable") {
    banner.className = "banner warn";
    banner.textContent = `Cannot reach uwuHere right now. Showing the list from ${formatTime(savedAt)}.${waiting}`;
  } else if (pending) {
    banner.className = "banner";
    banner.textContent = `Sending ${pending} saved check-in${pending === 1 ? "" : "s"}.`;
  } else {
    banner.hidden = true;
    return;
  }
  banner.hidden = false;
}

/* -------------------------------------------------------------------------
 * Same wifi check-in: this page is the P2P host
 * ---------------------------------------------------------------------- */

function wantP2p() {
  return Boolean(event && event.allowP2p && !event.ended && hostKey);
}

function syncP2p() {
  if (wantP2p() && !host && !retryTimer) startP2p();
  if (!wantP2p() && (host || retryTimer)) stopP2p();
  renderP2p();
}

async function startP2p() {
  const mine = new Host({ maxGuests: 40 });
  host = mine;
  p2p = { status: "connecting", message: "" };

  mine.addEventListener("status", ({ detail }) => {
    if (host !== mine) return;

    // Something else holds this code: usually this same page a moment ago,
    // before a reload, while the broker has not let the id go yet. The event
    // code cannot change, so wait and try again a few times rather than
    // moving to a fresh code as the spec does for a pairing code.
    if (detail.taken && takenRetries < TAKEN_RETRIES) {
      takenRetries += 1;
      host = null;
      mine.close();
      p2p = { status: "connecting", message: "" };
      retryTimer = setTimeout(() => {
        retryTimer = null;
        syncP2p();
      }, TAKEN_RETRY_MS);
      renderP2p();
      return;
    }

    if (detail.status === "waiting" || detail.status === "connected") takenRetries = 0;
    p2p = detail.taken
      ? { status: "error", message: "This event is already open on another screen. Same-wifi check-ins go to that one." }
      : detail;
    renderP2p();
    updateWakeLock();
  });

  mine.addEventListener("message", ({ detail: { message, from } }) => onPeerMessage(message, from));

  renderP2p();
  try {
    await mine.start(code);
  } catch {
    if (host !== mine) return;
    host = null;
    p2p = { status: "error", message: "Could not load same-wifi check-in. Check your connection." };
    renderP2p();
  }
}

function stopP2p() {
  clearTimeout(retryTimer);
  retryTimer = null;
  const old = host;
  host = null;
  old?.close();
  p2p = { status: "idle", message: "" };
  renderP2p();
  updateWakeLock();
}

function restartP2p() {
  stopP2p();
  takenRetries = 0;
  syncP2p();
}

function renderP2p() {
  const row = $("p2pRow");
  row.hidden = !event || !event.allowP2p || event.ended;
  if (row.hidden) return;

  const dot = $("p2pDot");
  dot.className = "status-dot";
  let text;
  let retry = false;

  switch (p2p.status) {
    case "waiting":
    case "connected":
      dot.classList.add("ok");
      text = "Ready for same-wifi check-ins. Keep this page open.";
      break;
    case "connecting":
      text = navigator.onLine ? "Starting same-wifi check-in." : "Same-wifi check-in needs a connection to start.";
      if (!navigator.onLine) dot.classList.add("warn");
      break;
    case "error":
      dot.classList.add("error");
      text = p2p.message || "Same-wifi check-in stopped.";
      retry = true;
      break;
    default:
      text = "Same-wifi check-in is not running.";
      retry = wantP2p();
  }

  $("p2pText").textContent = text;
  $("p2pRetry").hidden = !retry;
}

$("p2pRetry").addEventListener("click", restartP2p);

// Input from another device: checked field by field, never trusted.
function cleanLine(value, max) {
  if (typeof value !== "string") return "";
  const clean = value.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
  return charCount(clean) <= max ? clean : null;
}

async function onPeerMessage(message, from) {
  // bye, and any type a newer build might send: nothing to do.
  if (message.type !== "checkin") return;

  if (message.v !== PROTOCOL_VERSION) {
    host?.send({ type: "refused", reason: "version", message: "This page is out of date. Reload it and try again." }, from);
    return;
  }
  host?.send(await takeCheckin(message, "p2p"), from);
}

// A check-in this page received, by same wifi ("p2p") or through the app's
// hotspot ("hotspot"): to the server, or into the outbox if it can't be
// reached. Answers { type: "checked-in", at } or { type: "refused", reason,
// message }, the same-wifi protocol's own answers.
async function takeCheckin(message, method) {
  if (!event || event.ended) return { type: "refused", reason: "ended", message: "This event has ended." };
  if (event.paused) return { type: "refused", reason: "paused", message: "The host has paused check-ins for now." };

  const deviceHash =
    typeof message.deviceHash === "string" && /^[0-9a-f]{64}$/.test(message.deviceHash) ? message.deviceHash : null;
  const name = cleanLine(message.name, LIMITS.name);
  const note = event.noteLabel ? cleanLine(message.note, LIMITS.note) : "";

  if (!deviceHash || !name || note === null) {
    return { type: "refused", reason: "invalid", message: "That check-in was missing a name." };
  }

  // Already waiting in the outbox from this device: the same answer again.
  const queued = store.getOutbox(code).find((i) => i.kind === "record" && i.payload.deviceHash === deviceHash);
  if (queued) return { type: "checked-in", at: queued.payload.at };

  const payload = { deviceHash, name, note: note || null, at: new Date().toISOString(), method };
  const result = await postJson("host", { code, hostKey, action: "record", ...payload });

  if (result.ok) {
    setConnection("ok");
    upsertAttendee(result.data.attendee);
    render();
    return { type: "checked-in", at: result.data.attendee.checkedInAt };
  }

  const failure = connectionFailure(result);
  if (failure) {
    setConnection(failure);
    queue("record", payload);
    return { type: "checked-in", at: payload.at };
  }

  return { type: "refused", reason: result.reason, message: result.error };
}

/* -------------------------------------------------------------------------
 * Tapping phones: in the app, this phone is the NFC tag people touch
 * ---------------------------------------------------------------------- */

function wantTap() {
  return Boolean(event && event.allowTap && !event.ended && hostKey && AppBridge.has("tap"));
}

// Tells the app whether to answer taps, and with which event's key. Asked
// again with force when the page comes back, as NFC may have been switched
// on in the meantime.
async function syncTap({ force = false } = {}) {
  const want = wantTap();
  if (want === tapWanted && !force) return;
  tapWanted = want;
  try {
    const answer = await AppBridge.call("Here", "tap", want ? { on: true, code, hostKey } : { on: false });
    tapState = answer?.state || "idle";
  } catch {
    tapState = want ? "error" : "idle";
  }
  renderTap();
  updateWakeLock();
}

function renderTap() {
  const row = $("tapRow");
  row.hidden = !event || !event.allowTap || event.ended;
  if (row.hidden) return;

  const dot = $("tapDot");
  const action = $("tapAction");
  dot.className = "status-dot";
  action.hidden = true;
  let text;

  if (!bridgeHeard) {
    text = "Starting tap check-in.";
  } else if (!AppBridge.has("tap")) {
    dot.classList.add("warn");
    text = AppBridge.native
      ? "Update the uwuHere app to take taps."
      : "Tapping phones works in the uwuHere app on an Android phone with NFC. Open this event there.";
  } else if (tapState === "ready") {
    dot.classList.add("ok");
    text = "Ready for taps. People hold their phone against the back of this one.";
  } else if (tapState === "nfc-off") {
    dot.classList.add("warn");
    text = "NFC is off on this phone. Turn it on to take taps.";
    action.textContent = "Turn on";
    action.dataset.do = "nfc";
    action.hidden = false;
  } else if (tapState === "unsupported") {
    dot.classList.add("error");
    text = "This phone can't take taps: it has no NFC. Open this event in the app on a phone that has it.";
  } else if (tapState === "error") {
    dot.classList.add("error");
    text = "Tapping phones didn't start.";
    action.textContent = "Retry";
    action.dataset.do = "retry";
    action.hidden = false;
  } else {
    text = "Starting tap check-in.";
  }
  $("tapText").textContent = text;
}

$("tapAction").addEventListener("click", () => {
  if ($("tapAction").dataset.do === "nfc") AppBridge.call("Here", "openSettings", { what: "nfc" }).catch(() => {});
  else syncTap({ force: true });
});

// The app says so as a phone reads the link. The check-in itself shows in
// the list once they press the button on their phone.
AppBridge.listen("Here", "tapped", () => toast("Phone tapped. They finish on their phone."));

// Leaving this page, inside the app, stops the taps.
window.addEventListener("pagehide", () => {
  if (tapWanted) AppBridge.call("Here", "tap", { on: false }).catch(() => {});
});

/* -------------------------------------------------------------------------
 * Bluetooth: in the app, attendees' apps check in phone to phone
 * ---------------------------------------------------------------------- */

function wantBluetooth() {
  return Boolean(event && event.allowBluetooth && !event.ended && hostKey && AppBridge.has("mesh"));
}

// Advertises this event to attendees' apps, or stops. Without `ask` it never
// shows a permission prompt by itself: it says "needs-permission", and the
// row's button asks.
async function syncBluetooth({ force = false, ask = false } = {}) {
  const want = wantBluetooth();
  if (want === btWanted && !force && !ask) return;
  btWanted = want;
  try {
    const answer = await AppBridge.call("Here", "bluetooth", want ? { on: true, code, ask } : { on: false });
    btState = answer?.state || "idle";
    if (btState === "failed") btState = { failed: answer.message };
  } catch {
    btState = want ? { failed: "" } : "idle";
  }
  renderBluetooth();
  updateWakeLock();
}

function renderBluetooth() {
  const row = $("btRow");
  row.hidden = !event || !event.allowBluetooth || event.ended;
  if (row.hidden) return;

  const dot = $("btDot");
  const action = $("btAction");
  dot.className = "status-dot";
  action.hidden = true;
  const offer = (label, what) => {
    action.textContent = label;
    action.dataset.do = what;
    action.hidden = false;
  };
  let text;

  if (!bridgeHeard) {
    text = "Starting Bluetooth check-in.";
  } else if (!AppBridge.native) {
    dot.classList.add("warn");
    text = "Bluetooth check-in works with this event open in the uwuHere app on Android.";
  } else if (!AppBridge.has("mesh")) {
    dot.classList.add("error");
    text = AppBridge.has("hotspot")
      ? "This phone has no Google Play services, which Bluetooth check-in needs."
      : "Update the uwuHere app to take Bluetooth check-ins.";
  } else if (btState === "ready") {
    dot.classList.add("ok");
    text = "Ready for Bluetooth. Attendees with the uwuHere app check in phone to phone. Keep this page open.";
  } else if (btState === "needs-permission") {
    dot.classList.add("warn");
    text = "Bluetooth check-in needs \"Nearby devices\" on this phone.";
    offer("Allow", "ask");
  } else if (btState === "denied") {
    dot.classList.add("error");
    text = "\"Nearby devices\" isn't allowed for uwuHere. Allow it in the app's settings.";
    offer("Settings", "app");
  } else if (btState === "bt-off") {
    dot.classList.add("warn");
    text = "Bluetooth is off on this phone. Turn it on to take Bluetooth check-ins.";
    offer("Turn on", "bluetooth");
  } else if (typeof btState === "object") {
    dot.classList.add("error");
    text = btState.failed || "Bluetooth check-in didn't start.";
    offer("Retry", "retry");
  } else {
    text = "Starting Bluetooth check-in.";
  }
  $("btText").textContent = text;
}

$("btAction").addEventListener("click", () => {
  const what = $("btAction").dataset.do;
  if (what === "ask") syncBluetooth({ ask: true });
  else if (what === "app" || what === "bluetooth") AppBridge.call("Here", "openSettings", { what }).catch(() => {});
  else syncBluetooth({ force: true });
});

// A check-in from an attendee's app, waiting on this answer.
AppBridge.listen("Here", "meshCheckin", async (data) => {
  const answer = await takeCheckin(data, "mesh");
  AppBridge.call("Here", "meshAnswer", {
    id: data.id,
    ok: answer.type === "checked-in",
    at: answer.at || null,
    message: answer.message || null,
  }).catch(() => {});
});

// Leaving this page, inside the app, stops advertising.
window.addEventListener("pagehide", () => {
  if (btWanted) AppBridge.call("Here", "bluetooth", { on: false }).catch(() => {});
});

/* -------------------------------------------------------------------------
 * No internet: in the app, this phone is the attendees' wifi
 * ---------------------------------------------------------------------- */

// { status: "off" | "starting" | "on" | "failed", ssid, password, security,
// url, message }, from the app (Hotspot.java).
let hotspot = { status: "off" };

function renderHotspot() {
  const row = $("hotspotRow");
  row.hidden = !event || event.ended || !AppBridge.has("hotspot");
  if (row.hidden) return;

  const dot = $("hotspotDot");
  const action = $("hotspotAction");
  dot.className = "status-dot";
  dot.hidden = hotspot.status === "off";
  action.disabled = hotspot.status === "starting";

  if (hotspot.status === "on") {
    dot.classList.add("ok");
    $("hotspotText").textContent = `Hotspot on: ${hotspot.ssid}. Keep this page open.`;
    action.textContent = "Show codes";
  } else if (hotspot.status === "starting") {
    $("hotspotText").textContent = "Starting the hotspot.";
    action.textContent = "Start";
  } else if (hotspot.status === "failed") {
    dot.classList.add("error");
    $("hotspotText").textContent = hotspot.message || "The hotspot didn't start.";
    action.textContent = "Try again";
  } else {
    $("hotspotText").textContent = "No internet for attendees? This phone can be their wifi.";
    action.textContent = "Start";
  }
}

// WIFI:T:WPA;S:name;P:password;; is what phone cameras read as "join this
// wifi". \ ; , : and " are escaped with a backslash.
function wifiQrText({ ssid, password, security }) {
  const esc = (s) => String(s ?? "").replace(/([\\;,:"])/g, "\\$1");
  return security === "nopass"
    ? `WIFI:T:nopass;S:${esc(ssid)};;`
    : `WIFI:T:${security || "WPA"};S:${esc(ssid)};P:${esc(password)};;`;
}

function showHotspot() {
  if (hotspot.status !== "on") return;
  const wifi = wifiQrText(hotspot);
  $("hotspotWifiQr").innerHTML = qrToSvg(wifi, { label: `QR code to join the wifi ${hotspot.ssid}` });
  $("hotspotWifiText").textContent =
    hotspot.security === "nopass" ? `Wifi: ${hotspot.ssid}` : `Wifi: ${hotspot.ssid}, password ${hotspot.password}`;
  $("hotspotPageQr").innerHTML = qrToSvg(hotspot.url, { label: `QR code for ${hotspot.url}` });
  $("hotspotPageText").textContent = hotspot.url;
  openModal("hotspotModal");
  if (AppBridge.has("brightness")) AppBridge.call("Here", "brightness", { max: true }).catch(() => {});
}

async function startHotspot() {
  if (!event || event.ended || hotspot.status === "starting") return;
  hotspot = { status: "starting" };
  renderHotspot();
  try {
    const answer = await AppBridge.call("Here", "hotspot", {
      on: true,
      code,
      title: event.title || "",
      buttonLabel: event.buttonLabel,
      buttonColor: event.buttonColor,
      noteLabel: event.noteLabel || "",
    });
    hotspot = answer?.state === "on" ? { ...answer, status: "on" } : { status: "failed", message: answer?.message };
  } catch (cause) {
    hotspot = { status: "failed", message: cause?.message };
  }
  renderHotspot();
  updateWakeLock();
  if (hotspot.status === "on") showHotspot();
}

function stopHotspot() {
  if (hotspot.status === "off") return;
  hotspot = { status: "off" };
  AppBridge.call("Here", "hotspot", { on: false }).catch(() => {});
  closeIfOpen("hotspotModal");
  renderHotspot();
  updateWakeLock();
}

$("hotspotAction").addEventListener("click", () => {
  if (hotspot.status === "on") showHotspot();
  else startHotspot();
});

$("hotspotStop").addEventListener("click", stopHotspot);

// A check-in from the hotspot's page, waiting on this answer.
AppBridge.listen("Here", "hotspotCheckin", async (data) => {
  const answer = await takeCheckin(data, "hotspot");
  AppBridge.call("Here", "hotspotAnswer", {
    id: data.id,
    ok: answer.type === "checked-in",
    at: answer.at || null,
    message: answer.message || null,
  }).catch(() => {});
});

// Android stopped it, such as for its own wifi.
AppBridge.listen("Here", "hotspotStopped", () => {
  hotspot = { status: "failed", message: "The hotspot stopped. Start it again if people still need it." };
  closeIfOpen("hotspotModal");
  renderHotspot();
  updateWakeLock();
});

// Leaving this page, inside the app, stops the hotspot: its check-ins come here.
window.addEventListener("pagehide", () => {
  if (hotspot.status === "on" || hotspot.status === "starting") {
    AppBridge.call("Here", "hotspot", { on: false }).catch(() => {});
  }
});

// The host screen has to stay on for same-wifi check-ins to reach it, for
// taps to be answered, and for hotspot check-ins to be recorded.
let appAwake = false;

async function updateWakeLock() {
  const want =
    ((host && (p2p.status === "waiting" || p2p.status === "connected")) ||
      tapState === "ready" ||
      btState === "ready" ||
      hotspot.status === "on") &&
    document.visibilityState === "visible";

  // The app's WebView has no navigator.wakeLock, so the app keeps its own
  // window's screen on instead.
  if (AppBridge.has("keepawake")) {
    if (Boolean(want) !== appAwake) {
      appAwake = Boolean(want);
      AppBridge.call("Here", "keepAwake", { on: appAwake }).catch(() => {});
    }
    return;
  }

  if (want && !wakeLock && "wakeLock" in navigator) {
    try {
      wakeLock = await navigator.wakeLock.request("screen");
      wakeLock.addEventListener("release", () => {
        wakeLock = null;
      });
    } catch {
      // Refused (battery saver, an unfocused tab): the page still works.
    }
  } else if (!want && wakeLock) {
    wakeLock.release().catch(() => {});
    wakeLock = null;
  }
}

/* -------------------------------------------------------------------------
 * Actions
 * ---------------------------------------------------------------------- */

$("codeBtn").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(joinLink());
    toast("Link copied");
  } catch {
    toast("Copy the link under the code");
  }
});

/* ---- the big QR code ---- */

function showQr() {
  if (!event || event.ended) return;
  const link = joinLink();
  $("qrModalEvent").textContent = event.title || "";
  $("qrModalEvent").hidden = !event.title;
  $("qrModalCode").textContent = code;
  $("qrModalLink").textContent = link;
  if ($("qrModalHolder").dataset.link !== link) {
    $("qrModalHolder").innerHTML = qrToSvg(link, { label: `QR code for ${link}` });
    $("qrModalHolder").dataset.link = link;
  }
  openModal("qrModal");
  // In the app, the screen at full brightness while the code is up, so it
  // scans from the back of a room. The phone's own setting is left alone.
  if (AppBridge.has("brightness")) AppBridge.call("Here", "brightness", { max: true }).catch(() => {});
}

$("qrShowBtn").addEventListener("click", showQr);
$("qrTrayBtn").addEventListener("click", showQr);

document.addEventListener("uwu:modalclose", ({ detail }) => {
  if ((detail.id === "qrModal" || detail.id === "hotspotModal") && AppBridge.has("brightness")) {
    AppBridge.call("Here", "brightness", { max: false }).catch(() => {});
  }
});

$("pauseBtn").addEventListener("click", async () => {
  const button = $("pauseBtn");
  button.disabled = true;
  const result = await mutate(event.paused ? "resume" : "pause", {}, "Pausing needs a connection.");
  button.disabled = false;
  if (!result.ok) toast(result.error);
});

$("attendeeList").addEventListener("click", async (e) => {
  const button = e.target.closest("[data-remove]");
  if (!button || !armed(button, "Remove?")) return;

  if (button.dataset.pending) {
    store.saveOutbox(code, store.getOutbox(code).filter((i) => i.localId !== button.dataset.remove));
    render();
    return;
  }

  button.disabled = true;
  const result = await mutate("remove", { attendeeId: button.dataset.remove }, "Removing someone needs a connection.");
  if (!result.ok) {
    button.disabled = false;
    toast(result.error);
  }
});

$("addForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const name = $("addName").value.trim();
  const note = event.noteLabel ? $("addNote").value.trim() : "";
  if (!name) return $("addName").focus();

  const payload = { name, note: note || null, at: new Date().toISOString() };
  const result = await postJson("host", { code, hostKey, action: "add", ...payload });

  if (result.ok) {
    setConnection("ok");
    upsertAttendee(result.data.attendee);
  } else if (connectionFailure(result)) {
    setConnection(connectionFailure(result));
    queue("add", payload);
    toast("Saved on this device. It is sent when the connection is back.");
  } else {
    return toast(result.error);
  }

  $("addName").value = "";
  $("addNote").value = "";
  render();
  $("addName").focus();
});

/* ---- CSV ---- */

function stamp(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// A name is typed by an attendee. A cell that starts with = + - or @ is a
// formula to a spreadsheet, so it is defused with a leading apostrophe.
function csvCell(value) {
  let s = String(value ?? "");
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function downloadCsv() {
  if (!event) return;
  const rows = [["Name", event.noteLabel || "Note", "Checked in", "How", "Distance (m)", "Left early"]];
  for (const a of displayList().reverse()) {
    rows.push([
      a.name,
      a.note ?? "",
      stamp(a.checkedInAt),
      (METHOD[a.method] ?? METHOD.manual).label,
      a.distance ?? "",
      stamp(a.leftEarlyAt),
    ]);
  }

  // The byte order mark is what makes Excel read the file as UTF-8.
  const csv = "﻿" + rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
  const name = `uwuhere-${code}-${stamp(new Date().toISOString()).slice(0, 10)}.csv`;

  // The app's WebView cannot download a file the page made, so the app saves
  // it: into Downloads, or on older Android wherever the host picks.
  if (AppBridge.has("savefile")) {
    AppBridge.call("Here", "saveFile", { name, text: csv, mime: "text/csv" })
      .then((saved) => {
        if (saved.where === "downloads") toast(`Saved to Downloads as ${name}`);
        else if (saved.saved) toast("Saved");
      })
      .catch((cause) => toast(cause?.message || "Could not save the list."));
    return;
  }

  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

$("csvBtn").addEventListener("click", downloadCsv);
$("csvTrayBtn").addEventListener("click", downloadCsv);
$("endCsvBtn").addEventListener("click", downloadCsv);

/* ---- end ---- */

$("endBtn").addEventListener("click", () => {
  const pending = store.getOutbox(code).length;
  $("endText").textContent =
    `Check-ins close for everyone and the attendee page stops working. The list stays downloadable here ` +
    `for ${store.PURGE_AFTER_END_DAYS} days, then it is deleted.` +
    (pending ? ` ${pending} check-in${pending === 1 ? " is" : "s are"} still waiting to be sent from this device.` : "");
  $("endError").hidden = true;
  openModal("endModal");
});

$("endConfirm").addEventListener("click", async () => {
  const button = $("endConfirm");
  button.disabled = true;
  await flushOutbox();
  const result = await mutate("end", {}, "Ending the event needs a connection.");
  button.disabled = false;

  if (!result.ok) {
    $("endError").textContent = result.error;
    $("endError").hidden = false;
    return;
  }
  closeModal("endModal");
  toast("Event ended");
});

/* ---- settings ---- */

const settingsMethods = { p2p: true, location: false, tap: false, bluetooth: false };
let newSpot = null;

function bindCounter(inputId, countId, max) {
  const input = $(inputId);
  const update = () => {
    const n = charCount(input.value);
    $(countId).textContent = `${n}/${max}`;
    $(countId).classList.toggle("full", n >= max);
  };
  input.addEventListener("input", update);
  return update;
}

const counters = [
  bindCounter("sTitle", "sTitleCount", LIMITS.title),
  bindCounter("sButtonLabel", "sLabelCount", LIMITS.buttonLabel),
  bindCounter("sNoteLabel", "sNoteCount", LIMITS.noteLabel),
];

function updateSettingsPreview() {
  $("sPreviewLabel").textContent = $("sButtonLabel").value.trim() || "I'm here";
  paintHereButton($("sPreview"), $("sButtonColor").value);
}
$("sButtonLabel").addEventListener("input", updateSettingsPreview);
$("sButtonColor").addEventListener("input", updateSettingsPreview);

function renderSettingsMethods() {
  document.querySelectorAll("#sMethods [data-method]").forEach((btn) => {
    btn.setAttribute("aria-pressed", String(settingsMethods[btn.dataset.method]));
  });
  $("sLocationBlock").hidden = !settingsMethods.location;
}

$("sMethods").addEventListener("click", (e) => {
  const btn = e.target.closest("[data-method]");
  if (!btn) return;
  settingsMethods[btn.dataset.method] = !settingsMethods[btn.dataset.method];
  renderSettingsMethods();
});

function renderPasswordState() {
  $("passwordState").textContent = event.hasPassword
    ? "A password is set. Anyone with it can manage this event from another device."
    : "No password. Only this browser can manage this event.";
  $("clearPassword").hidden = !event.hasPassword;
  $("passwordError").hidden = true;
}

$("settingsBtn").addEventListener("click", () => {
  if (!event) return;
  $("sTitle").value = event.title;
  $("sButtonLabel").value = event.buttonLabel;
  $("sButtonColor").value = event.buttonColor;
  $("sNoteLabel").value = event.noteLabel ?? "";
  $("sRadius").value = String(event.radius);
  if (!$("sRadius").value) $("sRadius").value = "100";
  settingsMethods.p2p = event.allowP2p;
  settingsMethods.location = event.allowLocation;
  settingsMethods.tap = event.allowTap;
  settingsMethods.bluetooth = event.allowBluetooth;
  newSpot = null;
  $("sUseHere").setAttribute("aria-pressed", "false");
  $("sUseHereText").textContent = event.hasLocation ? "Move the spot to where I am now" : "Set the spot to where I am now";
  $("settingsError").hidden = true;
  $("sPassword").value = "";
  $("sPwChecks").hidden = true;
  counters.forEach((update) => update());
  updateSettingsPreview();
  renderSettingsMethods();
  renderPasswordState();
  openModal("settingsModal");
});

async function takeSpot() {
  $("sUseHereText").textContent = "Finding your location";
  try {
    newSpot = await getPosition();
    $("sUseHere").setAttribute("aria-pressed", "true");
    $("sUseHereText").textContent = `Spot set to here, within about ${Math.round(newSpot.accuracy)} m`;
    return true;
  } catch (cause) {
    $("sUseHereText").textContent = "Set the spot to where I am now";
    $("settingsError").textContent = cause.message;
    $("settingsError").hidden = false;
    return false;
  }
}

$("sUseHere").addEventListener("click", takeSpot);

$("settingsForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  $("settingsError").hidden = true;
  const fail = (message) => {
    $("settingsError").textContent = message;
    $("settingsError").hidden = false;
  };

  const buttonLabel = $("sButtonLabel").value.trim();
  if (!buttonLabel) return fail("The button needs some text.");
  if (!settingsMethods.p2p && !settingsMethods.location && !settingsMethods.tap && !settingsMethods.bluetooth) {
    return fail("Pick at least one way for people to check in.");
  }
  if (settingsMethods.location && !event.hasLocation && !newSpot && !(await takeSpot())) return;

  const settings = {
    title: $("sTitle").value,
    buttonLabel,
    buttonColor: $("sButtonColor").value,
    noteLabel: $("sNoteLabel").value,
    allowP2p: settingsMethods.p2p,
    allowLocation: settingsMethods.location,
    allowTap: settingsMethods.tap,
    allowBluetooth: settingsMethods.bluetooth,
    radius: Number($("sRadius").value),
  };
  if (newSpot) settings.location = newSpot;

  const result = await mutate("update", { settings }, "Changing settings needs a connection.");
  if (!result.ok) return fail(result.error);
  closeModal("settingsModal");
  toast("Saved");
});

$("sPassword").addEventListener("input", () => {
  renderPasswordChecks($("sPwChecks"), $("sPassword").value, { title: event?.title, code });
});

$("passwordForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const password = $("sPassword").value;
  if (!checkPassword(password, { title: event.title, code }).ok) {
    $("passwordError").textContent = "That password is not strong enough yet. See the checklist under it.";
    $("passwordError").hidden = false;
    return;
  }
  const result = await mutate("password", { password }, "Setting a password needs a connection.");
  if (!result.ok) {
    $("passwordError").textContent = result.error;
    $("passwordError").hidden = false;
    return;
  }
  $("sPassword").value = "";
  $("sPwChecks").hidden = true;
  renderPasswordState();
  toast("Password set");
});

$("clearPassword").addEventListener("click", async (e) => {
  if (!armed(e.currentTarget, "Remove it? Only this browser will manage the event")) return;
  const result = await mutate("password", { password: "" }, "Removing the password needs a connection.");
  if (!result.ok) {
    $("passwordError").textContent = result.error;
    $("passwordError").hidden = false;
    return;
  }
  renderPasswordState();
  toast("Password removed");
});

/* ---- unlock on another device ---- */

$("unlockForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const error = $("unlockError");
  error.hidden = true;

  const result = await postJson("unlock", { code, password: $("unlockPassword").value });
  if (!result.ok) {
    if (result.reason === "not-found") return eventGone();
    error.textContent = result.offline ? "Opening an event here needs a connection." : result.error;
    error.hidden = false;
    return;
  }

  $("unlockPassword").value = "";
  hostKey = result.data.hostKey;
  store.saveHosted(code, hostKey, result.data.event);
  applySnapshot(result.data);
  startPolling();
});

/* -------------------------------------------------------------------------
 * Boot
 * ---------------------------------------------------------------------- */

function startPolling() {
  clearInterval(pollTimer);
  pollTimer = setInterval(() => {
    if (document.visibilityState === "visible" && event && !event.ended) refresh();
  }, POLL_MS);
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState !== "visible" || !hostKey) {
    updateWakeLock();
    return;
  }
  refresh();
  // A phone that slept may have lost its peer.
  if (wantP2p() && (p2p.status === "error" || p2p.status === "idle")) restartP2p();
  syncTap({ force: true });
  // Bluetooth may have been switched on, or allowed, meanwhile.
  syncBluetooth({ force: true });
  updateWakeLock();
});

window.addEventListener("online", () => {
  refresh();
  if (wantP2p() && p2p.status !== "waiting" && p2p.status !== "connected") restartP2p();
});

window.addEventListener("offline", () => {
  setConnection("offline");
  renderP2p();
});

// In the app, same-wifi check-in can be up before the app has said what it
// can do; once it has, the screen is kept on if it should be, and taps are
// answered.
if (AppBridge.native) {
  AppBridge.ready(5000).then(() => {
    bridgeHeard = true;
    syncTap();
    renderTap();
    syncBluetooth();
    renderBluetooth();
    renderHotspot();
    updateWakeLock();
  });
}

async function boot() {
  if (!isValidCode(code)) {
    return showMissing("No event here", "This link has no event code. Make an event from the home page.");
  }

  hostKey = store.getHostKey(code);
  if (!hostKey) return showLocked();

  const cache = store.getHostCache(code);
  if (cache?.event) applySnapshot(cache, { fromCache: true });

  await refresh();

  if (!event && connection !== "ok") {
    return showMissing(
      "Not available offline",
      "This event has not been opened on this device before. Connect to the internet and reload."
    );
  }
  startPolling();
}

boot();
