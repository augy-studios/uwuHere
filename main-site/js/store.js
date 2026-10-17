// Everything uwuHere keeps in the browser, under the "uwuhere." prefix.
//
//   uwuhere.deviceId        this browser's random check-in id
//   uwuhere.profile         the name (and note) last typed, to prefill
//   uwuhere.hosted          events this browser manages: code -> host key
//   uwuhere.host.CODE       the host page's last copy of an event and list
//   uwuhere.outbox.CODE     host changes made offline, waiting to be sent
//   uwuhere.event.CODE      the attendee page's last copy of an event
//   uwuhere.attend.CODE     this browser's own check-in to an event
//   uwuhere.heldtap.CODE    a tap made with no connection, to send later
//
// Every read and write tolerates storage being unavailable (private mode,
// blocked site data): the app still works for the page view.

// How long the server keeps an event. Repeated from
// migrations/0002_uwuhere_purge.sql for the interface copy; change together.
export const PURGE_AFTER_END_DAYS = 7;
export const PURGE_UNENDED_DAYS = 30;

const PREFIX = "uwuhere.";

function read(key, fallback = null) {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    return raw === null ? fallback : JSON.parse(raw);
  } catch {
    return fallback;
  }
}

function write(key, value) {
  try {
    if (value === null || value === undefined) localStorage.removeItem(PREFIX + key);
    else localStorage.setItem(PREFIX + key, JSON.stringify(value));
  } catch {
    // Kept for this page view only.
  }
}

/* ---- device ---- */

let memoryDeviceId = null;

export function deviceId() {
  let id = read("deviceId");
  if (typeof id !== "string" || !/^[A-Za-z0-9-]{16,64}$/.test(id)) {
    id = memoryDeviceId ?? crypto.randomUUID();
    memoryDeviceId = id;
    write("deviceId", id);
  }
  return id;
}

/** SHA-256 of the device id, hex. What the host is given, never the id. */
export async function deviceHash() {
  const bytes = new TextEncoder().encode(deviceId());
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function getProfile() {
  return read("profile", { name: "", note: "" });
}

export function saveProfile(profile) {
  write("profile", { name: profile.name || "", note: profile.note || "" });
}

/* ---- hosting ---- */

export function listHosted() {
  const all = read("hosted", {});
  return Object.entries(all)
    .map(([code, info]) => ({ code, ...info }))
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
}

export function getHostKey(code) {
  return read("hosted", {})[code]?.hostKey ?? null;
}

export function saveHosted(code, hostKey, event) {
  const all = read("hosted", {});
  all[code] = {
    hostKey,
    title: event?.title ?? all[code]?.title ?? "",
    createdAt: event?.createdAt ?? all[code]?.createdAt ?? new Date().toISOString(),
    ended: Boolean(event?.ended),
  };
  write("hosted", all);
}

export function forgetHosted(code) {
  const all = read("hosted", {});
  delete all[code];
  write("hosted", all);
  write(`host.${code}`, null);
  write(`outbox.${code}`, null);
}

export function getHostCache(code) {
  return read(`host.${code}`);
}

export function saveHostCache(code, snapshot) {
  write(`host.${code}`, { ...snapshot, savedAt: new Date().toISOString() });
}

export function getOutbox(code) {
  return read(`outbox.${code}`, []);
}

export function saveOutbox(code, items) {
  write(`outbox.${code}`, items.length ? items : null);
}

/* ---- attending ---- */

export function getEventCache(code) {
  return read(`event.${code}`);
}

export function saveEventCache(code, event) {
  write(`event.${code}`, event);
}

export function getAttendance(code) {
  return read(`attend.${code}`);
}

export function saveAttendance(code, attendance) {
  write(`attend.${code}`, attendance);
}

/** { token, name, note, tappedAt }, or null. */
export function getHeldTap(code) {
  return read(`heldtap.${code}`);
}

export function saveHeldTap(code, held) {
  write(`heldtap.${code}`, held);
}
