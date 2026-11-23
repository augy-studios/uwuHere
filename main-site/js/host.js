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

/* -------------------------------------------------------------------------
 * Small helpers
 * ---------------------------------------------------------------------- */

// Finds an element on the page by its id.
function getElement(id) {
  return document.getElementById(id);
}

// Gives back `value` when it is truthy (not empty, zero, null and so on),
// and `fallback` otherwise.
function valueOrFallback(value, fallback) {
  if (value) {
    return value;
  }
  return fallback;
}

// Gives back `value`, or an empty string when it is null or undefined.
function valueOrEmptyText(value) {
  if (value === null || value === undefined) {
    return "";
  }
  return value;
}

// The `message` of an error or an answer, or undefined when there is no
// error or answer at all.
function messageOf(errorOrAnswer) {
  if (errorOrAnswer === null || errorOrAnswer === undefined) {
    return undefined;
  }
  return errorOrAnswer.message;
}

// Does nothing. Used to ignore a failed call to the app that nobody waits on.
function ignoreError() {}

const code = normaliseCode(new URLSearchParams(location.search).get("id"));

const POLL_INTERVAL_MILLISECONDS = 5000;
const MAXIMUM_TAKEN_RETRIES = 3;
const TAKEN_RETRY_DELAY_MILLISECONDS = 4000;
const MILLISECONDS_PER_DAY = 86400000;
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
let p2pState = { status: "idle", message: "" };
let takenRetryCount = 0;
let retryTimer = null;
let wakeLock = null;

// What the app last said about tapping phones: "idle", "ready", "nfc-off",
// "unsupported" or "error".
let tapState = "idle";
let tapWanted = false;
// What the app last said about Bluetooth check-in (Mesh.java): "idle",
// "ready", "needs-permission", "denied", "bt-off", "unsupported" or "failed".
let bluetoothState = "idle";
let bluetoothWanted = false;

// Whether the app has said what it can do yet (AppBridge.ready, at boot).
let bridgeHeard = !AppBridge.native;

/* -------------------------------------------------------------------------
 * Views
 * ---------------------------------------------------------------------- */

// Shows one of the page's three views and hides the others, along with the
// tray buttons that only make sense while hosting.
function show(view) {
  for (const id of ["missingView", "lockedView", "hostView"]) {
    getElement(id).hidden = id !== view;
  }
  const hosting = view === "hostView" && Boolean(event);
  getElement("qrTrayBtn").hidden = !hosting || event.ended;
  getElement("settingsBtn").hidden = !hosting || event.ended;
  getElement("csvTrayBtn").hidden = !hosting;
  if (!hosting || event.ended) {
    closeIfOpen("qrModal");
  }
}

function closeIfOpen(id) {
  if (!getElement(id).classList.contains("hidden")) {
    closeModal(id);
  }
}

function showMissing(title, text) {
  getElement("missingTitle").textContent = title;
  getElement("missingText").textContent = text;
  show("missingView");
}

function showLocked(message) {
  getElement("lockedText").textContent = valueOrFallback(message, "Enter the password set when this event was made.");
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
  if (result.offline) {
    return "offline";
  }
  if (result.status >= 500) {
    return "unavailable";
  }
  return null;
}

// Takes a whole copy of the event and its list, from the server or from the
// copy kept on this device, and brings the page and everything that hangs
// off it (storage, notifications, widget, P2P, taps, Bluetooth) up to date.
function applySnapshot(snapshot, { fromCache = false } = {}) {
  event = snapshot.event;
  if (Array.isArray(snapshot.attendees)) {
    attendees = snapshot.attendees;
  } else {
    attendees = [];
  }
  if (fromCache) {
    savedAt = snapshot.savedAt;
  } else {
    savedAt = new Date().toISOString();
  }
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

// Puts an attendee in the list, replacing the one with the same id if there
// is one already.
function addOrReplaceAttendee(attendee) {
  const existingIndex = attendees.findIndex((listedAttendee) => {
    return listedAttendee.id === attendee.id;
  });
  if (existingIndex === -1) {
    attendees.push(attendee);
  } else {
    attendees[existingIndex] = attendee;
  }
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

// Sends anything waiting in the outbox, then fetches the latest copy of the
// event from the server.
async function refresh() {
  if (!hostKey) {
    return;
  }
  await flushOutbox();

  const result = await postJson("host", { code, hostKey, action: "get" });
  if (result.ok) {
    setConnection("ok");
    applySnapshot(result.data);
    return;
  }

  const failure = connectionFailure(result);
  if (failure) {
    setConnection(failure);
    return;
  }
  if (result.reason === "not-host") {
    loseAccess();
    return;
  }
  if (result.reason === "not-found") {
    eventGone();
    return;
  }
}

/** A host action that answers with the whole snapshot. */
async function mutate(action, extraFields, offlineMessage) {
  const result = await postJson("host", { code, hostKey, action, ...extraFields });
  if (result.ok) {
    setConnection("ok");
    applySnapshot(result.data);
    return { ok: true };
  }

  const failure = connectionFailure(result);
  if (failure) {
    setConnection(failure);
    let errorMessage;
    if (failure === "offline") {
      errorMessage = offlineMessage;
    } else {
      errorMessage = result.error;
    }
    return { ok: false, error: errorMessage };
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

// Sends the outbox to the server, oldest first. Stops (and keeps the rest)
// as soon as the server is out of reach again.
async function flushOutbox() {
  if (flushing || !hostKey) {
    return;
  }
  flushing = true;

  try {
    let items = store.getOutbox(code);
    while (items.length > 0) {
      const firstItem = items[0];
      const result = await postJson("host", { code, hostKey, action: firstItem.kind, ...firstItem.payload });

      // Still unreachable, or this browser lost its key: keep everything for
      // the next attempt rather than dropping somebody's check-in.
      if (!result.ok && (connectionFailure(result) || result.reason === "not-host")) {
        break;
      }

      if (result.ok) {
        addOrReplaceAttendee(result.data.attendee);
      } else if (result.reason !== "ended") {
        toast(`Could not save ${firstItem.payload.name}: ${result.error}`);
      }

      items = store.getOutbox(code).filter((queuedItem) => {
        return queuedItem.localId !== firstItem.localId;
      });
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

// How a check-in method is shown, falling back to "Added by hand" for a
// method this page does not know.
function methodFor(methodName) {
  const method = METHOD[methodName];
  if (method === null || method === undefined) {
    return METHOD.manual;
  }
  return method;
}

function joinLink() {
  return `${location.origin}/join?id=${code}`;
}

// The list as shown: the server's attendees plus the check-ins still waiting
// in the outbox, newest first.
function displayList() {
  const pending = store.getOutbox(code).map((item) => {
    let method;
    if (item.kind === "record") {
      method = valueOrFallback(item.payload.method, "p2p");
    } else {
      method = "manual";
    }
    return {
      id: item.localId,
      name: item.payload.name,
      note: item.payload.note,
      method: method,
      distance: null,
      checkedInAt: item.payload.at,
      leftEarlyAt: null,
      pending: true,
    };
  });
  const combined = [...attendees, ...pending];
  return combined.sort((first, second) => {
    return String(second.checkedInAt).localeCompare(String(first.checkedInAt));
  });
}

// Draws the whole host view from `event` and the list.
function render() {
  if (!event) {
    return;
  }
  show("hostView");

  const ended = event.ended;
  document.title = `${valueOrFallback(event.title, code)} | uwuHere`;
  getElement("eventTitle").textContent = valueOrFallback(event.title, "Untitled event");

  const link = joinLink();
  getElement("codeBtn").textContent = code;
  getElement("shareLink").textContent = link;
  if (getElement("qrHolder").dataset.link !== link) {
    getElement("qrHolder").innerHTML = qrToSvg(link);
    getElement("qrHolder").dataset.link = link;
  }

  getElement("endedBanner").hidden = !ended;
  if (ended) {
    const purgeDate = new Date(
      Date.parse(event.endedAt) + store.PURGE_AFTER_END_DAYS * MILLISECONDS_PER_DAY
    ).toISOString();
    getElement("endedBanner").textContent =
      `Ended ${formatDateTime(event.endedAt)}. The list can be downloaded here until ` +
      `${formatDateTime(purgeDate)}, then it is deleted.`;
  }

  getElement("shareBlock").hidden = ended;
  if (ended) {
    stopHotspot();
  }
  getElement("pauseBtn").hidden = ended;
  getElement("endBtn").hidden = ended;
  getElement("addForm").hidden = ended;
  getElement("pausedBanner").hidden = ended || !event.paused;

  if (event.paused) {
    getElement("pauseBtn").innerHTML = `<span data-icon="play"></span>Resume`;
  } else {
    getElement("pauseBtn").innerHTML = `<span data-icon="pause"></span>Pause`;
  }
  hydrateIcons(getElement("pauseBtn"));

  getElement("locRow").hidden = !event.allowLocation || ended;
  if (event.hasLocation) {
    getElement("locText").textContent = `Location check-in within ${event.radius} m of this event's spot.`;
  } else {
    getElement("locText").textContent = "Location check-in is on, but no spot is set. Set one in Event settings.";
  }

  getElement("addNote").hidden = !event.noteLabel;
  getElement("addNote").placeholder = valueOrFallback(event.noteLabel, "");
  getElement("addNote").setAttribute("aria-label", valueOrFallback(event.noteLabel, "Note"));

  renderList();
  renderSync();
  renderP2p();
  renderTap();
  renderBluetooth();
  renderHotspot();
}

// The HTML for one row of the attendee list.
function attendeeRowHtml(attendee) {
  const method = methodFor(attendee.method);

  let methodDescription;
  if (attendee.distance === null || attendee.distance === undefined) {
    methodDescription = method.label;
  } else {
    methodDescription = `${method.label}, ${attendee.distance} m away`;
  }

  let noteHtml = "";
  if (attendee.note) {
    let notePrefix = "";
    if (event.noteLabel) {
      notePrefix = `${event.noteLabel}: `;
    }
    noteHtml = `<span class="attendee-note">${escapeHtml(notePrefix)}${escapeHtml(attendee.note)}</span>`;
  }

  let removeButtonHtml = "";
  if (!event.ended) {
    let pendingAttribute = "";
    if (attendee.pending) {
      pendingAttribute = 'data-pending="1"';
    }
    removeButtonHtml = `<button class="icon-btn small remove-btn" type="button" data-remove="${escapeHtml(attendee.id)}"
             ${pendingAttribute} aria-label="Remove ${escapeHtml(attendee.name)}" title="Remove">
             <span data-icon="trash"></span>
           </button>`;
  }

  let leftEarlyChipHtml = "";
  if (attendee.leftEarlyAt) {
    leftEarlyChipHtml = `<span class="chip warn"><span data-icon="door"></span>Left ${formatTime(attendee.leftEarlyAt)}</span>`;
  }

  let pendingChipHtml = "";
  if (attendee.pending) {
    pendingChipHtml = `<span class="chip busy">Not sent yet</span>`;
  }

  return `
        <li class="attendee">
          <span class="attendee-main">
            <span class="attendee-name">${escapeHtml(attendee.name)}</span>
            ${noteHtml}
          </span>
          <span class="attendee-meta">
            <span class="chip" title="${escapeHtml(methodDescription)}"><span data-icon="${method.icon}"></span>${formatTime(attendee.checkedInAt)}<span class="visually-hidden">, ${escapeHtml(methodDescription)}</span></span>
            ${leftEarlyChipHtml}
            ${pendingChipHtml}
          </span>
          ${removeButtonHtml}
        </li>`;
}

// Draws the attendee list, but only when something in it has changed, so a
// poll that brings nothing new does not rebuild it.
function renderList() {
  const list = displayList();
  const key = JSON.stringify([list, event.ended, event.noteLabel]);
  if (key === lastListKey) {
    return;
  }
  lastListKey = key;

  const leftEarlyCount = list.filter((attendee) => {
    return attendee.leftEarlyAt;
  }).length;

  let countText;
  if (list.length === 0) {
    countText = "";
  } else {
    let leftEarlyText = "";
    if (leftEarlyCount) {
      leftEarlyText = `, ${leftEarlyCount} left early`;
    }
    countText = `${list.length} checked in${leftEarlyText}`;
  }
  getElement("listCount").textContent = countText;
  getElement("emptyList").hidden = list.length > 0;

  getElement("attendeeList").innerHTML = list
    .map((attendee) => {
      return attendeeRowHtml(attendee);
    })
    .join("");
  hydrateIcons(getElement("attendeeList"));
}

// The banner that says the page is offline, or that saved check-ins are
// still being sent.
function renderSync() {
  const banner = getElement("syncBanner");
  const pendingCount = store.getOutbox(code).length;

  let pluralEnding = "s";
  if (pendingCount === 1) {
    pluralEnding = "";
  }

  let waitingText = "";
  if (pendingCount) {
    waitingText = ` ${pendingCount} check-in${pluralEnding} saved on this device will be sent when the connection is back.`;
  }

  if (connection === "offline") {
    banner.className = "banner warn";
    banner.textContent = `Offline. Showing the list from ${formatTime(savedAt)}.${waitingText}`;
  } else if (connection === "unavailable") {
    banner.className = "banner warn";
    banner.textContent = `Cannot reach uwuHere right now. Showing the list from ${formatTime(savedAt)}.${waitingText}`;
  } else if (pendingCount) {
    banner.className = "banner";
    banner.textContent = `Sending ${pendingCount} saved check-in${pluralEnding}.`;
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
  if (wantP2p() && !host && !retryTimer) {
    startP2p();
  }
  if (!wantP2p() && (host || retryTimer)) {
    stopP2p();
  }
  renderP2p();
}

// Opens this page to same-wifi check-ins under the event code. If the code
// is still held (usually by this page before a reload) it waits and tries
// again a few times.
async function startP2p() {
  const newHost = new Host({ maxGuests: 40 });
  host = newHost;
  p2pState = { status: "connecting", message: "" };

  newHost.addEventListener("status", ({ detail }) => {
    if (host !== newHost) {
      return;
    }

    // Something else holds this code: usually this same page a moment ago,
    // before a reload, while the broker has not let the id go yet. The event
    // code cannot change, so wait and try again a few times rather than
    // moving to a fresh code as the spec does for a pairing code.
    if (detail.taken && takenRetryCount < MAXIMUM_TAKEN_RETRIES) {
      takenRetryCount = takenRetryCount + 1;
      host = null;
      newHost.close();
      p2pState = { status: "connecting", message: "" };
      retryTimer = setTimeout(() => {
        retryTimer = null;
        syncP2p();
      }, TAKEN_RETRY_DELAY_MILLISECONDS);
      renderP2p();
      return;
    }

    if (detail.status === "waiting" || detail.status === "connected") {
      takenRetryCount = 0;
    }
    if (detail.taken) {
      p2pState = {
        status: "error",
        message: "This event is already open on another screen. Same-wifi check-ins go to that one.",
      };
    } else {
      p2pState = detail;
    }
    renderP2p();
    updateWakeLock();
  });

  newHost.addEventListener("message", ({ detail: { message, from } }) => {
    onPeerMessage(message, from);
  });

  renderP2p();
  try {
    await newHost.start(code);
  } catch {
    if (host !== newHost) {
      return;
    }
    host = null;
    p2pState = { status: "error", message: "Could not load same-wifi check-in. Check your connection." };
    renderP2p();
  }
}

function stopP2p() {
  clearTimeout(retryTimer);
  retryTimer = null;
  const previousHost = host;
  host = null;
  if (previousHost !== null && previousHost !== undefined) {
    previousHost.close();
  }
  p2pState = { status: "idle", message: "" };
  renderP2p();
  updateWakeLock();
}

function restartP2p() {
  stopP2p();
  takenRetryCount = 0;
  syncP2p();
}

// The same-wifi row: a coloured dot, a line of text, and a retry button.
function renderP2p() {
  const row = getElement("p2pRow");
  row.hidden = !event || !event.allowP2p || event.ended;
  if (row.hidden) {
    return;
  }

  const statusDot = getElement("p2pDot");
  statusDot.className = "status-dot";
  let statusText;
  let showRetry = false;

  switch (p2pState.status) {
    case "waiting":
    case "connected":
      statusDot.classList.add("ok");
      statusText = "Ready for same-wifi check-ins. Keep this page open.";
      break;
    case "connecting":
      if (navigator.onLine) {
        statusText = "Starting same-wifi check-in.";
      } else {
        statusText = "Same-wifi check-in needs a connection to start.";
        statusDot.classList.add("warn");
      }
      break;
    case "error":
      statusDot.classList.add("error");
      statusText = valueOrFallback(p2pState.message, "Same-wifi check-in stopped.");
      showRetry = true;
      break;
    default:
      statusText = "Same-wifi check-in is not running.";
      showRetry = wantP2p();
  }

  getElement("p2pText").textContent = statusText;
  getElement("p2pRetry").hidden = !showRetry;
}

getElement("p2pRetry").addEventListener("click", restartP2p);

// Input from another device: checked field by field, never trusted.
// Gives back the text on one line, "" when it is not text at all, or null
// when it is longer than `maximumLength` characters.
function cleanLine(value, maximumLength) {
  if (typeof value !== "string") {
    return "";
  }
  const cleaned = value.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
  if (charCount(cleaned) <= maximumLength) {
    return cleaned;
  }
  return null;
}

async function onPeerMessage(message, from) {
  // bye, and any type a newer build might send: nothing to do.
  if (message.type !== "checkin") {
    return;
  }

  if (message.v !== PROTOCOL_VERSION) {
    if (host !== null && host !== undefined) {
      host.send({ type: "refused", reason: "version", message: "This page is out of date. Reload it and try again." }, from);
    }
    return;
  }

  // The answer goes back through the host that was running when the message
  // came in, and only if one was.
  const answeringHost = host;
  if (answeringHost === null || answeringHost === undefined) {
    return;
  }
  const answer = await takeCheckin(message, "p2p");
  answeringHost.send(answer, from);
}

// A check-in this page received, by same wifi ("p2p") or through the app's
// hotspot ("hotspot"): to the server, or into the outbox if it can't be
// reached. Answers { type: "checked-in", at } or { type: "refused", reason,
// message }, the same-wifi protocol's own answers.
async function takeCheckin(message, method) {
  if (!event || event.ended) {
    return { type: "refused", reason: "ended", message: "This event has ended." };
  }
  if (event.paused) {
    return { type: "refused", reason: "paused", message: "The host has paused check-ins for now." };
  }

  let deviceHash = null;
  if (typeof message.deviceHash === "string" && /^[0-9a-f]{64}$/.test(message.deviceHash)) {
    deviceHash = message.deviceHash;
  }
  const name = cleanLine(message.name, LIMITS.name);
  let note = "";
  if (event.noteLabel) {
    note = cleanLine(message.note, LIMITS.note);
  }

  if (!deviceHash || !name || note === null) {
    return { type: "refused", reason: "invalid", message: "That check-in was missing a name." };
  }

  // Already waiting in the outbox from this device: the same answer again.
  const queued = store.getOutbox(code).find((item) => {
    return item.kind === "record" && item.payload.deviceHash === deviceHash;
  });
  if (queued) {
    return { type: "checked-in", at: queued.payload.at };
  }

  const payload = { deviceHash, name, note: valueOrFallback(note, null), at: new Date().toISOString(), method };
  const result = await postJson("host", { code, hostKey, action: "record", ...payload });

  if (result.ok) {
    setConnection("ok");
    addOrReplaceAttendee(result.data.attendee);
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

// The state the app reported in its answer, or "idle" when it reported none.
function stateFromAnswer(answer) {
  if (answer === null || answer === undefined) {
    return "idle";
  }
  return valueOrFallback(answer.state, "idle");
}

// Tells the app whether to answer taps, and with which event's key. Asked
// again with force when the page comes back, as NFC may have been switched
// on in the meantime.
async function syncTap({ force = false } = {}) {
  const wanted = wantTap();
  if (wanted === tapWanted && !force) {
    return;
  }
  tapWanted = wanted;
  try {
    let request;
    if (wanted) {
      request = { on: true, code, hostKey };
    } else {
      request = { on: false };
    }
    const answer = await AppBridge.call("Here", "tap", request);
    tapState = stateFromAnswer(answer);
  } catch {
    if (wanted) {
      tapState = "error";
    } else {
      tapState = "idle";
    }
  }
  renderTap();
  updateWakeLock();
}

// The tap row: a dot, a line of text, and a button when there is something
// the host can do about it.
function renderTap() {
  const row = getElement("tapRow");
  row.hidden = !event || !event.allowTap || event.ended;
  if (row.hidden) {
    return;
  }

  const statusDot = getElement("tapDot");
  const actionButton = getElement("tapAction");
  statusDot.className = "status-dot";
  actionButton.hidden = true;
  let statusText;

  if (!bridgeHeard) {
    statusText = "Starting tap check-in.";
  } else if (!AppBridge.has("tap")) {
    statusDot.classList.add("warn");
    if (AppBridge.native) {
      statusText = "Update the uwuHere app to take taps.";
    } else {
      statusText = "Tapping phones works in the uwuHere app on an Android phone with NFC. Open this event there.";
    }
  } else if (tapState === "ready") {
    statusDot.classList.add("ok");
    statusText = "Ready for taps. People hold their phone against the back of this one.";
  } else if (tapState === "nfc-off") {
    statusDot.classList.add("warn");
    statusText = "NFC is off on this phone. Turn it on to take taps.";
    actionButton.textContent = "Turn on";
    actionButton.dataset.do = "nfc";
    actionButton.hidden = false;
  } else if (tapState === "unsupported") {
    statusDot.classList.add("error");
    statusText = "This phone can't take taps: it has no NFC. Open this event in the app on a phone that has it.";
  } else if (tapState === "error") {
    statusDot.classList.add("error");
    statusText = "Tapping phones didn't start.";
    actionButton.textContent = "Retry";
    actionButton.dataset.do = "retry";
    actionButton.hidden = false;
  } else {
    statusText = "Starting tap check-in.";
  }
  getElement("tapText").textContent = statusText;
}

getElement("tapAction").addEventListener("click", () => {
  if (getElement("tapAction").dataset.do === "nfc") {
    AppBridge.call("Here", "openSettings", { what: "nfc" }).catch(ignoreError);
  } else {
    syncTap({ force: true });
  }
});

// The app says so as a phone reads the link. The check-in itself shows in
// the list once they press the button on their phone.
AppBridge.listen("Here", "tapped", () => {
  toast("Phone tapped. They finish on their phone.");
});

// Leaving this page, inside the app, stops the taps.
window.addEventListener("pagehide", () => {
  if (tapWanted) {
    AppBridge.call("Here", "tap", { on: false }).catch(ignoreError);
  }
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
  const wanted = wantBluetooth();
  if (wanted === bluetoothWanted && !force && !ask) {
    return;
  }
  bluetoothWanted = wanted;
  try {
    let request;
    if (wanted) {
      request = { on: true, code, ask };
    } else {
      request = { on: false };
    }
    const answer = await AppBridge.call("Here", "bluetooth", request);
    bluetoothState = stateFromAnswer(answer);
    if (bluetoothState === "failed") {
      bluetoothState = { failed: answer.message };
    }
  } catch {
    if (wanted) {
      bluetoothState = { failed: "" };
    } else {
      bluetoothState = "idle";
    }
  }
  renderBluetooth();
  updateWakeLock();
}

// The Bluetooth row: a dot, a line of text, and a button when there is
// something the host can do about it.
function renderBluetooth() {
  const row = getElement("btRow");
  row.hidden = !event || !event.allowBluetooth || event.ended;
  if (row.hidden) {
    return;
  }

  const statusDot = getElement("btDot");
  const actionButton = getElement("btAction");
  statusDot.className = "status-dot";
  actionButton.hidden = true;
  const offerAction = (label, actionName) => {
    actionButton.textContent = label;
    actionButton.dataset.do = actionName;
    actionButton.hidden = false;
  };
  let statusText;

  if (!bridgeHeard) {
    statusText = "Starting Bluetooth check-in.";
  } else if (!AppBridge.native) {
    statusDot.classList.add("warn");
    statusText = "Bluetooth check-in works with this event open in the uwuHere app on Android.";
  } else if (!AppBridge.has("mesh")) {
    statusDot.classList.add("error");
    if (AppBridge.has("hotspot")) {
      statusText = "This phone has no Google Play services, which Bluetooth check-in needs.";
    } else {
      statusText = "Update the uwuHere app to take Bluetooth check-ins.";
    }
  } else if (bluetoothState === "ready") {
    statusDot.classList.add("ok");
    statusText = "Ready for Bluetooth. Attendees with the uwuHere app check in phone to phone. Keep this page open.";
  } else if (bluetoothState === "needs-permission") {
    statusDot.classList.add("warn");
    statusText = "Bluetooth check-in needs \"Nearby devices\" on this phone.";
    offerAction("Allow", "ask");
  } else if (bluetoothState === "denied") {
    statusDot.classList.add("error");
    statusText = "\"Nearby devices\" isn't allowed for uwuHere. Allow it in the app's settings.";
    offerAction("Settings", "app");
  } else if (bluetoothState === "bt-off") {
    statusDot.classList.add("warn");
    statusText = "Bluetooth is off on this phone. Turn it on to take Bluetooth check-ins.";
    offerAction("Turn on", "bluetooth");
  } else if (typeof bluetoothState === "object") {
    statusDot.classList.add("error");
    statusText = valueOrFallback(bluetoothState.failed, "Bluetooth check-in didn't start.");
    offerAction("Retry", "retry");
  } else {
    statusText = "Starting Bluetooth check-in.";
  }
  getElement("btText").textContent = statusText;
}

getElement("btAction").addEventListener("click", () => {
  const requestedAction = getElement("btAction").dataset.do;
  if (requestedAction === "ask") {
    syncBluetooth({ ask: true });
  } else if (requestedAction === "app" || requestedAction === "bluetooth") {
    AppBridge.call("Here", "openSettings", { what: requestedAction }).catch(ignoreError);
  } else {
    syncBluetooth({ force: true });
  }
});

// A check-in from an attendee's app, waiting on this answer.
AppBridge.listen("Here", "meshCheckin", async (data) => {
  const answer = await takeCheckin(data, "mesh");
  AppBridge.call("Here", "meshAnswer", {
    id: data.id,
    ok: answer.type === "checked-in",
    at: valueOrFallback(answer.at, null),
    message: valueOrFallback(answer.message, null),
  }).catch(ignoreError);
});

// Leaving this page, inside the app, stops advertising.
window.addEventListener("pagehide", () => {
  if (bluetoothWanted) {
    AppBridge.call("Here", "bluetooth", { on: false }).catch(ignoreError);
  }
});

/* -------------------------------------------------------------------------
 * No internet: in the app, this phone is the attendees' wifi
 * ---------------------------------------------------------------------- */

// { status: "off" | "starting" | "on" | "failed", ssid, password, security,
// url, message }, from the app (Hotspot.java).
let hotspot = { status: "off" };

// The hotspot row: a dot, a line of text, and the start / show button.
function renderHotspot() {
  const row = getElement("hotspotRow");
  row.hidden = !event || event.ended || !AppBridge.has("hotspot");
  if (row.hidden) {
    return;
  }

  const statusDot = getElement("hotspotDot");
  const actionButton = getElement("hotspotAction");
  statusDot.className = "status-dot";
  statusDot.hidden = hotspot.status === "off";
  actionButton.disabled = hotspot.status === "starting";

  if (hotspot.status === "on") {
    statusDot.classList.add("ok");
    getElement("hotspotText").textContent = `Hotspot on: ${hotspot.ssid}. Keep this page open.`;
    actionButton.textContent = "Show codes";
  } else if (hotspot.status === "starting") {
    getElement("hotspotText").textContent = "Starting the hotspot.";
    actionButton.textContent = "Start";
  } else if (hotspot.status === "failed") {
    statusDot.classList.add("error");
    getElement("hotspotText").textContent = valueOrFallback(hotspot.message, "The hotspot didn't start.");
    actionButton.textContent = "Try again";
  } else {
    getElement("hotspotText").textContent = "No internet for attendees? This phone can be their wifi.";
    actionButton.textContent = "Start";
  }
}

// One value for a wifi QR code, with \ ; , : and " escaped by a backslash.
// Null or undefined becomes an empty string.
function escapeWifiValue(value) {
  let text = "";
  if (value !== null && value !== undefined) {
    text = String(value);
  }
  return text.replace(/([\\;,:"])/g, "\\$1");
}

// WIFI:T:WPA;S:name;P:password;; is what phone cameras read as "join this
// wifi". \ ; , : and " are escaped with a backslash.
function wifiQrText({ ssid, password, security }) {
  if (security === "nopass") {
    return `WIFI:T:nopass;S:${escapeWifiValue(ssid)};;`;
  }
  return `WIFI:T:${valueOrFallback(security, "WPA")};S:${escapeWifiValue(ssid)};P:${escapeWifiValue(password)};;`;
}

// Shows the two codes attendees scan: one to join the hotspot's wifi, then
// one for the check-in page it serves.
function showHotspot() {
  if (hotspot.status !== "on") {
    return;
  }
  const wifiText = wifiQrText(hotspot);
  getElement("hotspotWifiQr").innerHTML = qrToSvg(wifiText, { label: `QR code to join the wifi ${hotspot.ssid}` });
  if (hotspot.security === "nopass") {
    getElement("hotspotWifiText").textContent = `Wifi: ${hotspot.ssid}`;
  } else {
    getElement("hotspotWifiText").textContent = `Wifi: ${hotspot.ssid}, password ${hotspot.password}`;
  }
  getElement("hotspotPageQr").innerHTML = qrToSvg(hotspot.url, { label: `QR code for ${hotspot.url}` });
  getElement("hotspotPageText").textContent = hotspot.url;
  openModal("hotspotModal");
  if (AppBridge.has("brightness")) {
    AppBridge.call("Here", "brightness", { max: true }).catch(ignoreError);
  }
}

// Asks the app to start the hotspot and its check-in page for this event.
async function startHotspot() {
  if (!event || event.ended || hotspot.status === "starting") {
    return;
  }
  hotspot = { status: "starting" };
  renderHotspot();
  try {
    const answer = await AppBridge.call("Here", "hotspot", {
      on: true,
      code,
      title: valueOrFallback(event.title, ""),
      buttonLabel: event.buttonLabel,
      buttonColor: event.buttonColor,
      noteLabel: valueOrFallback(event.noteLabel, ""),
    });
    if (answer !== null && answer !== undefined && answer.state === "on") {
      hotspot = { ...answer, status: "on" };
    } else {
      hotspot = { status: "failed", message: messageOf(answer) };
    }
  } catch (cause) {
    hotspot = { status: "failed", message: messageOf(cause) };
  }
  renderHotspot();
  updateWakeLock();
  if (hotspot.status === "on") {
    showHotspot();
  }
}

function stopHotspot() {
  if (hotspot.status === "off") {
    return;
  }
  hotspot = { status: "off" };
  AppBridge.call("Here", "hotspot", { on: false }).catch(ignoreError);
  closeIfOpen("hotspotModal");
  renderHotspot();
  updateWakeLock();
}

getElement("hotspotAction").addEventListener("click", () => {
  if (hotspot.status === "on") {
    showHotspot();
  } else {
    startHotspot();
  }
});

getElement("hotspotStop").addEventListener("click", stopHotspot);

// A check-in from the hotspot's page, waiting on this answer.
AppBridge.listen("Here", "hotspotCheckin", async (data) => {
  const answer = await takeCheckin(data, "hotspot");
  AppBridge.call("Here", "hotspotAnswer", {
    id: data.id,
    ok: answer.type === "checked-in",
    at: valueOrFallback(answer.at, null),
    message: valueOrFallback(answer.message, null),
  }).catch(ignoreError);
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
    AppBridge.call("Here", "hotspot", { on: false }).catch(ignoreError);
  }
});

// The host screen has to stay on for same-wifi check-ins to reach it, for
// taps to be answered, and for hotspot check-ins to be recorded.
let appAwake = false;

// Keeps the screen on while any way of checking in is ready and the page is
// in view, and lets it sleep otherwise.
async function updateWakeLock() {
  const p2pReady = Boolean(host) && (p2pState.status === "waiting" || p2pState.status === "connected");
  const somethingIsReady =
    p2pReady || tapState === "ready" || bluetoothState === "ready" || hotspot.status === "on";
  const wanted = somethingIsReady && document.visibilityState === "visible";

  // The app's WebView has no navigator.wakeLock, so the app keeps its own
  // window's screen on instead.
  if (AppBridge.has("keepawake")) {
    if (wanted !== appAwake) {
      appAwake = wanted;
      AppBridge.call("Here", "keepAwake", { on: appAwake }).catch(ignoreError);
    }
    return;
  }

  if (wanted && !wakeLock && "wakeLock" in navigator) {
    try {
      wakeLock = await navigator.wakeLock.request("screen");
      wakeLock.addEventListener("release", () => {
        wakeLock = null;
      });
    } catch {
      // Refused (battery saver, an unfocused tab): the page still works.
    }
  } else if (!wanted && wakeLock) {
    wakeLock.release().catch(ignoreError);
    wakeLock = null;
  }
}

/* -------------------------------------------------------------------------
 * Actions
 * ---------------------------------------------------------------------- */

getElement("codeBtn").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(joinLink());
    toast("Link copied");
  } catch {
    toast("Copy the link under the code");
  }
});

/* ---- the big QR code ---- */

function showQr() {
  if (!event || event.ended) {
    return;
  }
  const link = joinLink();
  getElement("qrModalEvent").textContent = valueOrFallback(event.title, "");
  getElement("qrModalEvent").hidden = !event.title;
  getElement("qrModalCode").textContent = code;
  getElement("qrModalLink").textContent = link;
  if (getElement("qrModalHolder").dataset.link !== link) {
    getElement("qrModalHolder").innerHTML = qrToSvg(link, { label: `QR code for ${link}` });
    getElement("qrModalHolder").dataset.link = link;
  }
  openModal("qrModal");
  // In the app, the screen at full brightness while the code is up, so it
  // scans from the back of a room. The phone's own setting is left alone.
  if (AppBridge.has("brightness")) {
    AppBridge.call("Here", "brightness", { max: true }).catch(ignoreError);
  }
}

getElement("qrShowBtn").addEventListener("click", showQr);
getElement("qrTrayBtn").addEventListener("click", showQr);

document.addEventListener("uwu:modalclose", ({ detail }) => {
  if ((detail.id === "qrModal" || detail.id === "hotspotModal") && AppBridge.has("brightness")) {
    AppBridge.call("Here", "brightness", { max: false }).catch(ignoreError);
  }
});

getElement("pauseBtn").addEventListener("click", async () => {
  const button = getElement("pauseBtn");
  button.disabled = true;
  let action;
  if (event.paused) {
    action = "resume";
  } else {
    action = "pause";
  }
  const result = await mutate(action, {}, "Pausing needs a connection.");
  button.disabled = false;
  if (!result.ok) {
    toast(result.error);
  }
});

// The remove button on a row: a check-in still in the outbox is simply
// dropped; one on the server is removed there.
getElement("attendeeList").addEventListener("click", async (clickEvent) => {
  const button = clickEvent.target.closest("[data-remove]");
  if (!button || !armed(button, "Remove?")) {
    return;
  }

  if (button.dataset.pending) {
    const remainingItems = store.getOutbox(code).filter((item) => {
      return item.localId !== button.dataset.remove;
    });
    store.saveOutbox(code, remainingItems);
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

// Adding somebody by hand. With no connection they go into the outbox.
getElement("addForm").addEventListener("submit", async (submitEvent) => {
  submitEvent.preventDefault();
  const name = getElement("addName").value.trim();
  let note = "";
  if (event.noteLabel) {
    note = getElement("addNote").value.trim();
  }
  if (!name) {
    getElement("addName").focus();
    return;
  }

  const payload = { name, note: valueOrFallback(note, null), at: new Date().toISOString() };
  const result = await postJson("host", { code, hostKey, action: "add", ...payload });

  if (result.ok) {
    setConnection("ok");
    addOrReplaceAttendee(result.data.attendee);
  } else if (connectionFailure(result)) {
    setConnection(connectionFailure(result));
    queue("add", payload);
    toast("Saved on this device. It is sent when the connection is back.");
  } else {
    toast(result.error);
    return;
  }

  getElement("addName").value = "";
  getElement("addNote").value = "";
  render();
  getElement("addName").focus();
});

/* ---- CSV ---- */

// A number as two digits, with a leading zero when it needs one.
function padToTwoDigits(number) {
  return String(number).padStart(2, "0");
}

// An ISO time as "YYYY-MM-DD HH:MM" in local time, or "" for no time.
function spreadsheetTimestamp(isoText) {
  if (!isoText) {
    return "";
  }
  const date = new Date(isoText);
  return `${date.getFullYear()}-${padToTwoDigits(date.getMonth() + 1)}-${padToTwoDigits(date.getDate())} ${padToTwoDigits(date.getHours())}:${padToTwoDigits(date.getMinutes())}`;
}

// A name is typed by an attendee. A cell that starts with = + - or @ is a
// formula to a spreadsheet, so it is defused with a leading apostrophe.
function csvCell(value) {
  let text = "";
  if (value !== null && value !== undefined) {
    text = String(value);
  }
  if (/^[=+\-@\t\r]/.test(text)) {
    text = `'${text}`;
  }
  if (/[",\r\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

// Builds the list as a CSV file, oldest first, and saves it: through the app
// in the Android app, or as a normal download in a browser.
function downloadCsv() {
  if (!event) {
    return;
  }
  const rows = [["Name", valueOrFallback(event.noteLabel, "Note"), "Checked in", "How", "Distance (m)", "Left early"]];
  for (const attendee of displayList().reverse()) {
    rows.push([
      attendee.name,
      valueOrEmptyText(attendee.note),
      spreadsheetTimestamp(attendee.checkedInAt),
      methodFor(attendee.method).label,
      valueOrEmptyText(attendee.distance),
      spreadsheetTimestamp(attendee.leftEarlyAt),
    ]);
  }

  // The byte order mark is what makes Excel read the file as UTF-8.
  const csvLines = rows.map((row) => {
    return row.map(csvCell).join(",");
  });
  const csvText = "﻿" + csvLines.join("\r\n");
  const fileName = `uwuhere-${code}-${spreadsheetTimestamp(new Date().toISOString()).slice(0, 10)}.csv`;

  // The app's WebView cannot download a file the page made, so the app saves
  // it: into Downloads, or on older Android wherever the host picks.
  if (AppBridge.has("savefile")) {
    AppBridge.call("Here", "saveFile", { name: fileName, text: csvText, mime: "text/csv" })
      .then((saved) => {
        if (saved.where === "downloads") {
          toast(`Saved to Downloads as ${fileName}`);
        } else if (saved.saved) {
          toast("Saved");
        }
      })
      .catch((cause) => {
        toast(valueOrFallback(messageOf(cause), "Could not save the list."));
      });
    return;
  }

  const url = URL.createObjectURL(new Blob([csvText], { type: "text/csv;charset=utf-8" }));
  const downloadLink = document.createElement("a");
  downloadLink.href = url;
  downloadLink.download = fileName;
  document.body.append(downloadLink);
  downloadLink.click();
  downloadLink.remove();
  setTimeout(() => {
    URL.revokeObjectURL(url);
  }, 1000);
}

getElement("csvBtn").addEventListener("click", downloadCsv);
getElement("csvTrayBtn").addEventListener("click", downloadCsv);
getElement("endCsvBtn").addEventListener("click", downloadCsv);

/* ---- end ---- */

getElement("endBtn").addEventListener("click", () => {
  const pendingCount = store.getOutbox(code).length;
  let waitingText = "";
  if (pendingCount) {
    let ending;
    if (pendingCount === 1) {
      ending = " is";
    } else {
      ending = "s are";
    }
    waitingText = ` ${pendingCount} check-in${ending} still waiting to be sent from this device.`;
  }
  getElement("endText").textContent =
    `Check-ins close for everyone and the attendee page stops working. The list stays downloadable here ` +
    `for ${store.PURGE_AFTER_END_DAYS} days, then it is deleted.` +
    waitingText;
  getElement("endError").hidden = true;
  openModal("endModal");
});

getElement("endConfirm").addEventListener("click", async () => {
  const button = getElement("endConfirm");
  button.disabled = true;
  await flushOutbox();
  const result = await mutate("end", {}, "Ending the event needs a connection.");
  button.disabled = false;

  if (!result.ok) {
    getElement("endError").textContent = result.error;
    getElement("endError").hidden = false;
    return;
  }
  closeModal("endModal");
  toast("Event ended");
});

/* ---- settings ---- */

const settingsMethods = { p2p: true, location: false, tap: false, bluetooth: false };
let newSpot = null;

// Keeps a "12/80" character count next to a text box. Gives back the
// function that updates it, to call when the box is filled in by code.
function bindCounter(inputId, countId, maximumLength) {
  const input = getElement(inputId);
  const updateCount = () => {
    const characterTotal = charCount(input.value);
    getElement(countId).textContent = `${characterTotal}/${maximumLength}`;
    getElement(countId).classList.toggle("full", characterTotal >= maximumLength);
  };
  input.addEventListener("input", updateCount);
  return updateCount;
}

const counters = [
  bindCounter("sTitle", "sTitleCount", LIMITS.title),
  bindCounter("sButtonLabel", "sLabelCount", LIMITS.buttonLabel),
  bindCounter("sNoteLabel", "sNoteCount", LIMITS.noteLabel),
];

function updateSettingsPreview() {
  getElement("sPreviewLabel").textContent = valueOrFallback(getElement("sButtonLabel").value.trim(), "I'm here");
  paintHereButton(getElement("sPreview"), getElement("sButtonColor").value);
}
getElement("sButtonLabel").addEventListener("input", updateSettingsPreview);
getElement("sButtonColor").addEventListener("input", updateSettingsPreview);

function renderSettingsMethods() {
  document.querySelectorAll("#sMethods [data-method]").forEach((methodButton) => {
    methodButton.setAttribute("aria-pressed", String(settingsMethods[methodButton.dataset.method]));
  });
  getElement("sLocationBlock").hidden = !settingsMethods.location;
}

getElement("sMethods").addEventListener("click", (clickEvent) => {
  const methodButton = clickEvent.target.closest("[data-method]");
  if (!methodButton) {
    return;
  }
  settingsMethods[methodButton.dataset.method] = !settingsMethods[methodButton.dataset.method];
  renderSettingsMethods();
});

function renderPasswordState() {
  if (event.hasPassword) {
    getElement("passwordState").textContent = "A password is set. Anyone with it can manage this event from another device.";
  } else {
    getElement("passwordState").textContent = "No password. Only this browser can manage this event.";
  }
  getElement("clearPassword").hidden = !event.hasPassword;
  getElement("passwordError").hidden = true;
}

// Opens the settings dialog filled in with the event as it is now.
getElement("settingsBtn").addEventListener("click", () => {
  if (!event) {
    return;
  }
  getElement("sTitle").value = event.title;
  getElement("sButtonLabel").value = event.buttonLabel;
  getElement("sButtonColor").value = event.buttonColor;
  getElement("sNoteLabel").value = valueOrEmptyText(event.noteLabel);
  getElement("sRadius").value = String(event.radius);
  if (!getElement("sRadius").value) {
    getElement("sRadius").value = "100";
  }
  settingsMethods.p2p = event.allowP2p;
  settingsMethods.location = event.allowLocation;
  settingsMethods.tap = event.allowTap;
  settingsMethods.bluetooth = event.allowBluetooth;
  newSpot = null;
  getElement("sUseHere").setAttribute("aria-pressed", "false");
  if (event.hasLocation) {
    getElement("sUseHereText").textContent = "Move the spot to where I am now";
  } else {
    getElement("sUseHereText").textContent = "Set the spot to where I am now";
  }
  getElement("settingsError").hidden = true;
  getElement("sPassword").value = "";
  getElement("sPwChecks").hidden = true;
  counters.forEach((updateCount) => {
    updateCount();
  });
  updateSettingsPreview();
  renderSettingsMethods();
  renderPasswordState();
  openModal("settingsModal");
});

// Reads where this phone is now as the event's new spot. Gives back whether
// that worked.
async function takeSpot() {
  getElement("sUseHereText").textContent = "Finding your location";
  try {
    newSpot = await getPosition();
    getElement("sUseHere").setAttribute("aria-pressed", "true");
    getElement("sUseHereText").textContent = `Spot set to here, within about ${Math.round(newSpot.accuracy)} m`;
    return true;
  } catch (cause) {
    getElement("sUseHereText").textContent = "Set the spot to where I am now";
    getElement("settingsError").textContent = cause.message;
    getElement("settingsError").hidden = false;
    return false;
  }
}

getElement("sUseHere").addEventListener("click", takeSpot);

function showSettingsError(message) {
  getElement("settingsError").textContent = message;
  getElement("settingsError").hidden = false;
}

// Saving the settings dialog: checks it, finds a spot if location check-in
// needs one, and sends the new settings to the server.
getElement("settingsForm").addEventListener("submit", async (submitEvent) => {
  submitEvent.preventDefault();
  getElement("settingsError").hidden = true;

  const buttonLabel = getElement("sButtonLabel").value.trim();
  if (!buttonLabel) {
    showSettingsError("The button needs some text.");
    return;
  }
  if (!settingsMethods.p2p && !settingsMethods.location && !settingsMethods.tap && !settingsMethods.bluetooth) {
    showSettingsError("Pick at least one way for people to check in.");
    return;
  }
  if (settingsMethods.location && !event.hasLocation && !newSpot && !(await takeSpot())) {
    return;
  }

  const settings = {
    title: getElement("sTitle").value,
    buttonLabel,
    buttonColor: getElement("sButtonColor").value,
    noteLabel: getElement("sNoteLabel").value,
    allowP2p: settingsMethods.p2p,
    allowLocation: settingsMethods.location,
    allowTap: settingsMethods.tap,
    allowBluetooth: settingsMethods.bluetooth,
    radius: Number(getElement("sRadius").value),
  };
  if (newSpot) {
    settings.location = newSpot;
  }

  const result = await mutate("update", { settings }, "Changing settings needs a connection.");
  if (!result.ok) {
    showSettingsError(result.error);
    return;
  }
  closeModal("settingsModal");
  toast("Saved");
});

getElement("sPassword").addEventListener("input", () => {
  let eventTitle;
  if (event === null || event === undefined) {
    eventTitle = undefined;
  } else {
    eventTitle = event.title;
  }
  renderPasswordChecks(getElement("sPwChecks"), getElement("sPassword").value, { title: eventTitle, code });
});

getElement("passwordForm").addEventListener("submit", async (submitEvent) => {
  submitEvent.preventDefault();
  const password = getElement("sPassword").value;
  if (!checkPassword(password, { title: event.title, code }).ok) {
    getElement("passwordError").textContent = "That password is not strong enough yet. See the checklist under it.";
    getElement("passwordError").hidden = false;
    return;
  }
  const result = await mutate("password", { password }, "Setting a password needs a connection.");
  if (!result.ok) {
    getElement("passwordError").textContent = result.error;
    getElement("passwordError").hidden = false;
    return;
  }
  getElement("sPassword").value = "";
  getElement("sPwChecks").hidden = true;
  renderPasswordState();
  toast("Password set");
});

getElement("clearPassword").addEventListener("click", async (clickEvent) => {
  if (!armed(clickEvent.currentTarget, "Remove it? Only this browser will manage the event")) {
    return;
  }
  const result = await mutate("password", { password: "" }, "Removing the password needs a connection.");
  if (!result.ok) {
    getElement("passwordError").textContent = result.error;
    getElement("passwordError").hidden = false;
    return;
  }
  renderPasswordState();
  toast("Password removed");
});

/* ---- unlock on another device ---- */

// The event's password, typed on a device that did not make the event,
// gives this browser the host key.
getElement("unlockForm").addEventListener("submit", async (submitEvent) => {
  submitEvent.preventDefault();
  const errorElement = getElement("unlockError");
  errorElement.hidden = true;

  const result = await postJson("unlock", { code, password: getElement("unlockPassword").value });
  if (!result.ok) {
    if (result.reason === "not-found") {
      eventGone();
      return;
    }
    if (result.offline) {
      errorElement.textContent = "Opening an event here needs a connection.";
    } else {
      errorElement.textContent = result.error;
    }
    errorElement.hidden = false;
    return;
  }

  getElement("unlockPassword").value = "";
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
    if (document.visibilityState === "visible" && event && !event.ended) {
      refresh();
    }
  }, POLL_INTERVAL_MILLISECONDS);
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState !== "visible" || !hostKey) {
    updateWakeLock();
    return;
  }
  refresh();
  // A phone that slept may have lost its peer.
  if (wantP2p() && (p2pState.status === "error" || p2pState.status === "idle")) {
    restartP2p();
  }
  syncTap({ force: true });
  // Bluetooth may have been switched on, or allowed, meanwhile.
  syncBluetooth({ force: true });
  updateWakeLock();
});

window.addEventListener("online", () => {
  refresh();
  if (wantP2p() && p2pState.status !== "waiting" && p2pState.status !== "connected") {
    restartP2p();
  }
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

// Starts the page: shows the copy kept on this device straight away, if
// there is one, then the server's.
async function boot() {
  if (!isValidCode(code)) {
    showMissing("No event here", "This link has no event code. Make an event from the home page.");
    return;
  }

  hostKey = store.getHostKey(code);
  if (!hostKey) {
    showLocked();
    return;
  }

  const cachedSnapshot = store.getHostCache(code);
  if (cachedSnapshot !== null && cachedSnapshot !== undefined && cachedSnapshot.event) {
    applySnapshot(cachedSnapshot, { fromCache: true });
  }

  await refresh();

  if (!event && connection !== "ok") {
    showMissing(
      "Not available offline",
      "This event has not been opened on this device before. Connect to the internet and reload."
    );
    return;
  }
  startPolling();
}

boot();
