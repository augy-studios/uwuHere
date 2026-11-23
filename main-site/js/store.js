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
    const storedText = localStorage.getItem(PREFIX + key);
    if (storedText === null) {
      return fallback;
    }
    return JSON.parse(storedText);
  } catch {
    return fallback;
  }
}

// Saves a value as JSON, or removes the key when the value is null or undefined.
function write(key, value) {
  try {
    if (value === null || value === undefined) {
      localStorage.removeItem(PREFIX + key);
    } else {
      localStorage.setItem(PREFIX + key, JSON.stringify(value));
    }
  } catch {
    // Kept for this page view only.
  }
}

/* ---- device ---- */

let memoryDeviceId = null;

export function deviceId() {
  let id = read("deviceId");
  if (typeof id !== "string" || !/^[A-Za-z0-9-]{16,64}$/.test(id)) {
    if (memoryDeviceId === null || memoryDeviceId === undefined) {
      id = crypto.randomUUID();
    } else {
      id = memoryDeviceId;
    }
    memoryDeviceId = id;
    write("deviceId", id);
  }
  return id;
}

/** SHA-256 of the device id, hex. What the host is given, never the id. */
export async function deviceHash() {
  const bytes = new TextEncoder().encode(deviceId());
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => {
      return byte.toString(16).padStart(2, "0");
    })
    .join("");
}

export function getProfile() {
  return read("profile", { name: "", note: "" });
}

export function saveProfile(profile) {
  let name = "";
  if (profile.name) {
    name = profile.name;
  }
  let note = "";
  if (profile.note) {
    note = profile.note;
  }
  write("profile", { name, note });
}

/* ---- hosting ---- */

// Whether a value is neither null nor undefined.
function isPresent(value) {
  return value !== null && value !== undefined;
}

// The events this browser manages, newest first.
export function listHosted() {
  const hostedEvents = read("hosted", {});
  return Object.entries(hostedEvents)
    .map(([code, info]) => {
      return { code, ...info };
    })
    .sort((first, second) => {
      return String(second.createdAt).localeCompare(String(first.createdAt));
    });
}

export function getHostKey(code) {
  const hostedEvent = read("hosted", {})[code];
  if (isPresent(hostedEvent) && isPresent(hostedEvent.hostKey)) {
    return hostedEvent.hostKey;
  }
  return null;
}

// Remembers (or updates) an event this browser manages. The title and
// creation time come from the event when given, otherwise from what was
// already stored, otherwise a blank title and now.
export function saveHosted(code, hostKey, event) {
  const hostedEvents = read("hosted", {});
  const previous = hostedEvents[code];

  let title = "";
  if (isPresent(event) && isPresent(event.title)) {
    title = event.title;
  } else if (isPresent(previous) && isPresent(previous.title)) {
    title = previous.title;
  }

  let createdAt;
  if (isPresent(event) && isPresent(event.createdAt)) {
    createdAt = event.createdAt;
  } else if (isPresent(previous) && isPresent(previous.createdAt)) {
    createdAt = previous.createdAt;
  } else {
    createdAt = new Date().toISOString();
  }

  let ended = false;
  if (isPresent(event)) {
    ended = Boolean(event.ended);
  }

  hostedEvents[code] = {
    hostKey,
    title,
    createdAt,
    ended,
  };
  write("hosted", hostedEvents);
}

export function forgetHosted(code) {
  const hostedEvents = read("hosted", {});
  delete hostedEvents[code];
  write("hosted", hostedEvents);
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
  if (items.length) {
    write(`outbox.${code}`, items);
  } else {
    write(`outbox.${code}`, null);
  }
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
