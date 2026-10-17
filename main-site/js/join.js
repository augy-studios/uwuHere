// The attendee page: /join?id=CODE
//
// One big button. Pressing it proves the attendee is near the host, by the
// first method the event allows that works:
//
//   1. Tapping phones. Touching the host's phone hands over a link with a
//      one-time token (api/_lib/tap.js). It opens this page in a new tab,
//      which checks in at once with the name already typed, and this tab
//      follows (the storage event below). In Chrome on Android, a page already
//      open reads the tap itself instead (Web NFC), with no new tab.
//      With no connection, the tap is kept in this browser and sent once
//      there is one, marked as sent late (api/_lib/tap.js). A browser that has
//      opened uwuHere before has this page cached, so it opens offline.
//   2. Same wifi. A direct P2P channel to the host's open page. No permission
//      prompt, and almost always means the same network.
//   3. Location. One reading, sent to the server, which checks the distance
//      and keeps only the distance.
//
// **Once per browser.** A check-in that succeeded is remembered here and the
// button stays done, whatever happens later. The server also refuses a
// second row from the same device, so a cleared lock alone does not double
// count. A failed attempt does not use the tap up.
//
// "I'm leaving early" sits under it, unlocks after check-in, and works once.

import { bootShell } from "./shell.js";
import { api, postJson } from "./api.js";
import { Guest, normaliseCode, isValidCode, PROTOCOL_VERSION } from "./p2p.js";
import { getPosition } from "./geo.js";
import * as store from "./store.js";
import {
  formatTime, hydrateIcons, openModal, closeModal, toast, charCount, paintHereButton, hereLabelSize,
} from "./ui.js";

bootShell();

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const code = normaliseCode(params.get("id"));

// From a tap on the host's phone. Taken out of the address straight away, so
// the link left in the address bar, shared or bookmarked, carries no token.
let tapToken = params.get("tap");
if (tapToken) {
  params.delete("tap");
  history.replaceState(null, "", `${location.pathname}?${params}`);
}

const TAP_HOW = "Hold the top of your phone against the back of the host's phone.";
const OFFLINE_TAP = "You're offline. Press the button and your tap is kept, then sent once you're back online.";

// Opened by a tap: checks in by itself once the event has loaded, if the
// name is already filled in. Touching phones is the press.
let autoTap = Boolean(tapToken);

// The time a tap token says it was made, from its first part.
function tapTime(token) {
  const seconds = Number(String(token).split(".")[0]);
  return Number.isFinite(seconds) && seconds > 0 ? new Date(seconds * 1000).toISOString() : new Date().toISOString();
}

// Chrome on Android can read the tap in this page (Web NFC). Elsewhere the
// phone's own tag reading opens the link in a new tab.
const canReadTags = "NDEFReader" in window;
let tagScan = null; // an AbortController while listening

// How long to wait for the host's page to answer once the channel is open.
// It saves to the server before answering, so this covers a slow request.
const ANSWER_TIMEOUT_MS = 12000;

const PAUSED = "The host has paused check-ins for now.";

const UNREACHABLE =
  "Could not reach the host's screen. Join the same wifi as the host, or their phone's hotspot, then try again.";

let event = null;
let attendance = isValidCode(code) ? store.getAttendance(code) : null;
let busy = false;

/* -------------------------------------------------------------------------
 * Views
 * ---------------------------------------------------------------------- */

function showView(view) {
  for (const id of ["codeView", "messageView", "checkinView"]) $(id).hidden = id !== view;
}

function showMessage(title, text, { action = "another" } = {}) {
  $("messageTitle").textContent = title;
  $("messageText").textContent = text;
  const link = $("messageAction");
  link.hidden = action === null;
  if (action === "reload") {
    link.href = location.href;
    link.lastChild.textContent = "Try again";
  } else {
    link.href = "/join";
    link.lastChild.textContent = "Try another code";
  }
  showView("messageView");
}

function setStatus(message, tone = "") {
  const el = $("hereStatus");
  el.textContent = message;
  el.className = `here-status${tone ? ` ${tone}` : ""}`;
}

function render() {
  if (!event) return;

  if (event.ended) {
    const mine = attendance?.checkedInAt
      ? ` You checked in at ${formatTime(attendance.checkedInAt)}` +
        (attendance.leftEarlyAt ? ` and left at ${formatTime(attendance.leftEarlyAt)}.` : ".")
      : "";
    return showMessage("This event has ended", `Check-ins are closed.${mine}`, { action: null });
  }

  showView("checkinView");
  document.title = `${event.title || "Check in"} | uwuHere`;
  $("eventTitle").textContent = event.title || "Check in";
  $("eventCode").textContent = `Event ${event.code}`;

  const button = $("hereBtn");
  paintHereButton(button, event.buttonColor);

  const checked = Boolean(attendance?.checkedInAt);
  $("whoCard").hidden = checked;
  $("noteField").hidden = !event.noteLabel;
  $("noteLabel").textContent = event.noteLabel || "";

  $("hereIcon").hidden = !checked;
  $("hereSub").hidden = !checked;
  if (checked) {
    $("hereLabel").textContent = "You're here";
    $("hereSub").textContent = attendance.held
      ? `Tapped at ${formatTime(attendance.checkedInAt)}, not sent yet`
      : `Checked in at ${formatTime(attendance.checkedInAt)}`;
    button.style.setProperty("--here-size", "1.7rem");
  } else {
    $("hereLabel").textContent = event.buttonLabel;
    button.style.setProperty("--here-size", hereLabelSize(event.buttonLabel));
  }

  const blocked = checked || busy || event.paused;
  button.setAttribute("aria-disabled", String(blocked));
  button.classList.toggle("is-paused", event.paused && !checked);
  button.classList.toggle("is-busy", busy);
  button.setAttribute("aria-busy", String(busy));

  $("doneCard").hidden = !checked || !attendance.name;
  $("doneCard").textContent = !checked
    ? ""
    : attendance.held
      ? `Tapped as ${attendance.name}. It's sent as soon as this phone is back online.`
      : `Checked in as ${attendance.name}.`;

  const left = attendance?.leftEarlyAt;
  $("nfcBtn").hidden = !canReadTags || !event.allowTap || checked || Boolean(tagScan);
  if (checked) stopTagScan();

  $("leaveBtn").disabled = !checked || Boolean(attendance?.held) || Boolean(left) || busy;
  $("leaveText").textContent = left ? `Left at ${formatTime(left)}` : "I'm leaving early";

  // The paused notice comes and goes with the host; any other status stays.
  if (event.paused && !checked && !busy) setStatus(PAUSED);
  else if ($("hereStatus").textContent === PAUSED) setStatus("");

  const ways = [];
  if (event.allowTap) ways.push("tapping your phone on the host's phone");
  if (event.allowP2p) ways.push("being on the same wifi as the host");
  if (event.allowLocation) ways.push(`being within ${event.radius} m of the host (your location is used once, and only the distance is kept)`);
  $("methodNote").textContent = checked || event.offlineStub ? "" : `Checks that you are here by ${ways.join(", or by ")}.`;
}

/* -------------------------------------------------------------------------
 * Loading
 * ---------------------------------------------------------------------- */

// The server's record fills in what this browser does not know, such as a
// check-in made before site data was cleared. It never unlocks the button:
// a host removing somebody does not hand them a second tap.
function reconcile(me) {
  if (!me) return;
  attendance = {
    ...(attendance ?? {}),
    checkedInAt: attendance?.checkedInAt ?? me.checkedInAt,
    leftEarlyAt: me.leftEarlyAt ?? attendance?.leftEarlyAt ?? null,
  };
  store.saveAttendance(code, attendance);
}

async function load() {
  const result = await api(`event?code=${code}`, { headers: { "X-Uwuhere-Device": store.deviceId() } });

  if (result.ok) {
    const { me, ...rest } = result.data;
    event = rest;
    store.saveEventCache(code, event);
    reconcile(me);
    render();
    startTagScanIfAllowed();
    sendHeldTap();
    runAutoTap();
    return;
  }

  if (result.reason === "not-found") {
    store.saveEventCache(code, null);
    event = null;
    return showMessage("No event with that code", "Check the code on the host's screen and try again.");
  }

  if (event) {
    // A cached copy is on screen already; say why it may be out of date.
    if (result.offline && !busy && !attendance?.checkedInAt) {
      setStatus(tapToken ? OFFLINE_TAP : "You're offline. Checking in needs a connection.");
    }
    if (result.offline) runAutoTap();
    return;
  }

  // Opened by a tap with no connection, at an event this browser hasn't
  // seen: enough of a page to take the name and keep the tap.
  if (result.offline && tapToken) {
    event = {
      code,
      title: "",
      buttonLabel: "I'm here",
      buttonColor: "#ccffcc",
      noteLabel: null,
      allowTap: true,
      allowP2p: false,
      allowLocation: false,
      radius: 0,
      paused: false,
      ended: false,
      offlineStub: true,
    };
    render();
    setStatus(OFFLINE_TAP);
    runAutoTap();
    return;
  }

  if (result.offline) {
    return showMessage("You're offline", "Connect to the internet, then try again.", { action: "reload" });
  }
  showMessage("Something went wrong", result.error, { action: "reload" });
}

/* -------------------------------------------------------------------------
 * Checking in
 * ---------------------------------------------------------------------- */

function cleanLine(value) {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function viaP2p(name, note) {
  return new Promise((resolve) => {
    const guest = new Guest();
    let settled = false;
    let answerTimer = null;

    const finish = (outcome) => {
      if (settled) return;
      settled = true;
      clearTimeout(answerTimer);
      // Leaving on purpose sends bye; a failure just hangs up.
      if (outcome.ok) guest.leave();
      else guest.close();
      resolve(outcome);
    };

    guest.addEventListener("status", async ({ detail }) => {
      switch (detail.status) {
        case "connected":
          setStatus("Found the host. Checking you in.");
          guest.send({
            type: "checkin",
            v: PROTOCOL_VERSION,
            deviceHash: await store.deviceHash(),
            name,
            note: note || null,
          });
          answerTimer = setTimeout(
            () => finish({ ok: false, message: "The host's screen did not answer. Try again." }),
            ANSWER_TIMEOUT_MS
          );
          break;
        case "unreachable":
          finish({ ok: false, message: UNREACHABLE });
          break;
        case "dropped":
          finish({ ok: false, message: "The connection to the host dropped. Try again." });
          break;
        case "error":
          finish({
            ok: false,
            message: detail.type === "peer-unavailable" ? `${detail.message} Ask the host to open their page.` : detail.message,
          });
          break;
        default:
          break;
      }
    });

    guest.addEventListener("message", ({ detail: { message } }) => {
      if (message.type === "checked-in") {
        const at = typeof message.at === "string" && !Number.isNaN(Date.parse(message.at)) ? message.at : new Date().toISOString();
        finish({ ok: true, at, method: "p2p" });
      } else if (message.type === "refused") {
        const reason = typeof message.reason === "string" ? message.reason : "";
        if (reason === "paused" && event) event.paused = true;
        if (reason === "ended" && event) event.ended = true;
        finish({
          ok: false,
          // Shown with textContent, and capped: it came from another device.
          message: typeof message.message === "string" ? message.message.slice(0, 200) : "The host could not check you in.",
          // These would fail by location just the same.
          fallback: !["paused", "ended", "version", "invalid"].includes(reason),
        });
      } else if (message.type === "full") {
        finish({ ok: false, message: "The host's screen is busy. Try again in a moment." });
      }
    });

    guest.connect(code).catch(() => {
      finish({ ok: false, message: "Could not load same-wifi check-in. Check your connection." });
    });
  });
}

async function viaTap(name, note) {
  setStatus("Checking you in with the tap.");
  const result = await postJson("checkin", {
    code,
    deviceId: store.deviceId(),
    name,
    note: note || null,
    tap: tapToken,
  });

  if (result.ok) return { ok: true, at: result.data.attendee.checkedInAt, method: "tap" };

  // No connection: the tap is kept, and sent when there is one.
  if (result.offline) {
    const held = { token: tapToken, name, note: note || null, tappedAt: tapTime(tapToken) };
    store.saveHeldTap(code, held);
    tapToken = null;
    return { ok: true, held: true, at: held.tappedAt, method: "tap" };
  }

  // Spent, stale or broken: no use trying it again.
  if (["tap-bad", "tap-old", "tap-used"].includes(result.reason)) tapToken = null;
  if (result.reason === "ended") event.ended = true;
  if (result.reason === "paused") event.paused = true;
  return {
    ok: false,
    message: result.error,
    fallback: !["ended", "paused", "invalid"].includes(result.reason),
  };
}

// A tap kept while offline, sent now if there's a connection. Called when
// the event loads and when the phone comes back online.
let sendingHeld = false;
async function sendHeldTap() {
  const held = store.getHeldTap(code);
  if (!held || sendingHeld) return;
  sendingHeld = true;
  try {
    const result = await postJson("checkin", {
      code,
      deviceId: store.deviceId(),
      name: held.name,
      note: held.note,
      tap: held.token,
      late: true,
    });
    if (result.offline) return;

    store.saveHeldTap(code, null);
    if (result.ok) {
      attendance = { ...(attendance ?? {}), checkedInAt: result.data.attendee.checkedInAt, held: false, name: held.name };
      store.saveAttendance(code, attendance);
      setStatus(`Your tap from ${formatTime(held.tappedAt)} was sent. You're checked in.`, "ok");
    } else {
      // Refused for good, such as an event that ended meanwhile: the button
      // is free again, unless this browser checked in some other way.
      if (attendance?.held) {
        attendance = null;
        store.saveAttendance(code, null);
      }
      if (result.reason === "ended" && event) event.ended = true;
      setStatus(`Your tap from ${formatTime(held.tappedAt)} couldn't be sent: ${result.error}`, "error");
    }
    render();
  } finally {
    sendingHeld = false;
  }
}

window.addEventListener("online", sendHeldTap);

// Opened by a tap: check in by itself if the name is already filled in.
function runAutoTap() {
  if (!autoTap || !event) return;
  autoTap = false;
  if (cleanLine($("nameInput").value) && event.allowTap && !attendance?.checkedInAt) checkIn();
}

/* ---- reading the tap in this page (Web NFC, Chrome on Android) ---- */

function stopTagScan() {
  tagScan?.abort();
  tagScan = null;
}

// The host's phone hands over one link: this event's join page with a tap
// token. Anything else touched is ignored.
function onTag({ message }) {
  for (const record of message.records) {
    if (record.recordType !== "url") continue;
    let url;
    try {
      url = new URL(new TextDecoder().decode(record.data));
    } catch {
      continue;
    }
    if (url.origin !== location.origin || normaliseCode(url.searchParams.get("id")) !== code) continue;
    const token = url.searchParams.get("tap");
    if (!token) continue;
    tapToken = token;
    if (busy) return;
    if (!cleanLine($("nameInput").value)) {
      setStatus("Tapped. Type your name, then press the button.");
      $("nameInput").focus();
      return;
    }
    checkIn();
    return;
  }
}

async function startTagScan() {
  if (!canReadTags || tagScan || !event?.allowTap || attendance?.checkedInAt) return;
  const controller = new AbortController();
  tagScan = controller;
  try {
    const reader = new NDEFReader();
    reader.addEventListener("reading", onTag);
    await reader.scan({ signal: controller.signal });
    if (!busy && !attendance?.checkedInAt) setStatus(`Ready. ${TAP_HOW}`);
  } catch (cause) {
    if (tagScan === controller) tagScan = null;
    if (cause?.name === "NotAllowedError") setStatus("NFC wasn't allowed. Allow it in Chrome's site settings to tap.", "error");
    else if (cause?.name === "NotReadableError") setStatus("Turn on NFC in your phone's settings, then try again.", "error");
  }
  render();
}

// Without asking: only once this site has been allowed NFC before. The first
// time needs a press (the button under the big one), for Chrome's prompt.
async function startTagScanIfAllowed() {
  if (!canReadTags || tagScan || !event?.allowTap || attendance?.checkedInAt) return;
  try {
    const permission = await navigator.permissions.query({ name: "nfc" });
    if (permission.state === "granted") startTagScan();
  } catch {
    // No way to ask: the button is there.
  }
}

$("nfcBtn").addEventListener("click", startTagScan);

async function viaLocation(name, note) {
  let position;
  try {
    position = await getPosition();
  } catch (cause) {
    return { ok: false, message: cause.message };
  }

  setStatus("Checking your distance from the host.");
  const result = await postJson("checkin", {
    code,
    deviceId: store.deviceId(),
    name,
    note: note || null,
    position,
  });

  if (result.ok) return { ok: true, at: result.data.attendee.checkedInAt, method: "location" };

  if (result.reason === "ended") event.ended = true;
  if (result.reason === "paused") event.paused = true;
  return { ok: false, message: result.offline ? "You're offline. Checking in needs a connection." : result.error };
}

async function checkIn() {
  if (busy || !event || event.ended || attendance?.checkedInAt) return;
  if (event.paused) return setStatus(PAUSED);

  const name = cleanLine($("nameInput").value);
  const note = event.noteLabel ? cleanLine($("noteInput").value) : "";
  if (!name) {
    setStatus("Type your name first.", "error");
    $("nameInput").focus();
    return;
  }
  if (charCount(name) > 60) return setStatus("Your name can be at most 60 characters.", "error");
  if (charCount(note) > 120) return setStatus(`${event.noteLabel} can be at most 120 characters.`, "error");
  // Tapping is the only way in, and there's been no tap yet.
  if (event.allowTap && !tapToken && !event.allowP2p && !event.allowLocation) {
    if (canReadTags && !tagScan) startTagScan();
    return setStatus(TAP_HOW);
  }
  store.saveProfile({ name, note });

  busy = true;
  render();

  try {
    let outcome = { ok: false, message: "" };

    if (event.allowTap && tapToken) outcome = await viaTap(name, note);

    if (!outcome.ok && event.allowP2p && outcome.fallback !== false && !event.ended) {
      setStatus("Looking for the host's screen on this wifi.");
      outcome = await viaP2p(name, note);
    }

    if (!outcome.ok && event.allowLocation && outcome.fallback !== false && !event.ended) {
      setStatus(event.allowP2p ? "Not on the host's wifi. Checking your location instead." : "Checking your location.");
      outcome = await viaLocation(name, note);
    }

    if (outcome.ok) {
      attendance = { checkedInAt: outcome.at, method: outcome.method, leftEarlyAt: null, name, held: Boolean(outcome.held) };
      store.saveAttendance(code, attendance);
      setStatus(outcome.held ? "Tap kept. It's sent as soon as this phone is back online." : "You're checked in.", "ok");
    } else {
      setStatus(outcome.message || "Could not check you in. Try again.", "error");
    }
  } finally {
    busy = false;
    render();
  }
}

$("hereBtn").addEventListener("click", checkIn);

// Kept as it's typed, so a tap that opens this page in a new tab finds the
// name already there and can check in by itself.
for (const id of ["nameInput", "noteInput"]) {
  $(id).addEventListener("input", () => {
    store.saveProfile({ name: cleanLine($("nameInput").value), note: cleanLine($("noteInput").value) });
  });
}

// A check-in made in another tab of this browser, such as the one a tap
// opened: this tab shows it too.
window.addEventListener("storage", (e) => {
  if (e.key !== `uwuhere.attend.${code}` || !isValidCode(code)) return;
  const theirs = store.getAttendance(code);
  if (!theirs?.checkedInAt || attendance?.checkedInAt) return;
  attendance = theirs;
  setStatus("You're checked in.", "ok");
  render();
});

/* -------------------------------------------------------------------------
 * Leaving early
 * ---------------------------------------------------------------------- */

$("leaveBtn").addEventListener("click", () => {
  if (!attendance?.checkedInAt || attendance.leftEarlyAt) return;
  $("leaveError").hidden = true;
  openModal("leaveModal");
});

$("leaveConfirm").addEventListener("click", async () => {
  const button = $("leaveConfirm");
  button.disabled = true;
  const result = await postJson("leave", { code, deviceId: store.deviceId() });
  button.disabled = false;

  if (!result.ok) {
    if (result.reason === "ended") {
      event.ended = true;
      closeModal("leaveModal");
      return render();
    }
    $("leaveError").textContent = result.offline ? "You're offline. Leaving early needs a connection." : result.error;
    $("leaveError").hidden = false;
    return;
  }

  attendance = { ...attendance, leftEarlyAt: result.data.attendee.leftEarlyAt };
  store.saveAttendance(code, attendance);
  closeModal("leaveModal");
  render();
  toast("The host can see you left early");
});

/* -------------------------------------------------------------------------
 * No code in the link
 * ---------------------------------------------------------------------- */

$("codeInput").addEventListener("input", (e) => {
  const caret = e.target.selectionStart;
  e.target.value = e.target.value.toUpperCase();
  e.target.setSelectionRange(caret, caret);
  $("codeError").hidden = true;
});

$("codeForm").addEventListener("submit", (e) => {
  e.preventDefault();
  const typed = normaliseCode($("codeInput").value);
  if (!isValidCode(typed)) {
    $("codeError").textContent = "An event code is 6 letters and numbers, like BCD234.";
    $("codeError").hidden = false;
    return;
  }
  location.href = `/join?id=${typed}`;
});

/* -------------------------------------------------------------------------
 * Boot
 * ---------------------------------------------------------------------- */

document.addEventListener("visibilitychange", () => {
  // Back from another app: the host may have paused or ended meanwhile.
  if (document.visibilityState === "visible" && event && !busy) load();
});

if (!isValidCode(code)) {
  showView("codeView");
} else {
  const profile = store.getProfile();
  $("nameInput").value = profile.name;
  $("noteInput").value = profile.note;
  hydrateIcons();

  event = store.getEventCache(code);
  if (event) render();
  if (tapToken && !attendance?.checkedInAt) setStatus("Tapped. Press the button to check in.");
  load();
}
