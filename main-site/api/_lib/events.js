/* Reading and shaping events and attendees.

   The database speaks snake_case and the client camelCase. The two view
   functions here are the only places a row is turned into something sent
   to a browser, so a column that must never leave the server, such as
   password_hash or device_hash, is left out in exactly one place. */

import { rest, firstRow } from "./supabase.js";
import { HttpError, databaseError } from "./http.js";
import * as validate from "./validate.js";

const EVENT_COLUMNS = [
  "id", "code", "title", "button_label", "button_color", "note_label",
  "allow_p2p", "allow_location", "allow_tap", "allow_bluetooth", "host_lat", "host_lng", "host_accuracy_m",
  "radius_m", "password_hash", "paused", "created_at", "ended_at",
].join(",");

const ATTENDEE_COLUMNS = "id,name,note,method,distance_m,checked_in_at,left_early_at";

export async function findEvent(code) {
  const result = await rest("uwuhere_events", {
    query: { code: `eq.${code}`, select: EVENT_COLUMNS, limit: "1" },
  });
  if (!result.ok) {
    throw databaseError(result);
  }
  return firstRow(result);
}

export async function requireEvent(code) {
  const row = await findEvent(code);
  if (!row) {
    throw new HttpError(404, "There is no event with that code. Check it and try again.", "not-found");
  }
  return row;
}

/** What anybody holding the code may see. */
export function publicEvent(row) {
  return {
    code: row.code,
    title: row.title,
    buttonLabel: row.button_label,
    buttonColor: row.button_color,
    noteLabel: row.note_label,
    allowP2p: row.allow_p2p,
    allowLocation: row.allow_location,
    allowTap: row.allow_tap,
    allowBluetooth: row.allow_bluetooth,
    hasLocation: row.host_lat !== null,
    radius: row.radius_m,
    paused: row.paused,
    createdAt: row.created_at,
    ended: row.ended_at !== null,
    endedAt: row.ended_at,
  };
}

// Where the host set the check-in spot, or null when no spot is set.
function hostLocation(row) {
  if (row.host_lat === null) {
    return null;
  }
  return { lat: row.host_lat, lng: row.host_lng, accuracy: row.host_accuracy_m };
}

/** What the host sees: everything public, and whether a password is set. */
export function hostEvent(row) {
  return {
    ...publicEvent(row),
    hasPassword: Boolean(row.password_hash),
    location: hostLocation(row),
  };
}

export function publicAttendee(row) {
  let distance = null;
  if (row.distance_m !== null) {
    distance = Math.round(row.distance_m);
  }
  return {
    id: row.id,
    name: row.name,
    note: row.note,
    method: row.method,
    distance,
    checkedInAt: row.checked_in_at,
    leftEarlyAt: row.left_early_at,
  };
}

export async function listAttendees(eventId) {
  const result = await rest("uwuhere_attendees", {
    query: { event_id: `eq.${eventId}`, select: ATTENDEE_COLUMNS, order: "checked_in_at.asc" },
  });
  if (!result.ok) {
    throw databaseError(result);
  }
  let rows = result.data;
  if (rows === null || rows === undefined) {
    rows = [];
  }
  return rows.map(publicAttendee);
}

export async function findAttendeeByDevice(eventId, deviceHash) {
  const result = await rest("uwuhere_attendees", {
    query: { event_id: `eq.${eventId}`, device_hash: `eq.${deviceHash}`, select: ATTENDEE_COLUMNS, limit: "1" },
  });
  if (!result.ok) {
    throw databaseError(result);
  }
  return firstRow(result);
}

/**
 * Inserts a check-in, or finds the one this device already made.
 * Resolves to { attendee, already }.
 */
export async function insertAttendee(eventId, row) {
  const result = await rest("uwuhere_attendees", {
    method: "POST",
    query: { on_conflict: "event_id,device_hash", select: ATTENDEE_COLUMNS },
    prefer: "resolution=ignore-duplicates,return=representation",
    body: [{ event_id: eventId, ...row }],
  });
  // The tap token's nonce is unique (_lib/tap.js): this one made a check-in
  // already. A second check-in from the same device is not this, but the
  // ignored duplicate below.
  if (result.status === 409 && row.tap_nonce) {
    throw new HttpError(409, "That tap has been used already. Tap your phone on the host's phone again.", "tap-used");
  }
  if (!result.ok) {
    throw databaseError(result);
  }

  const inserted = firstRow(result);
  if (inserted) {
    return { attendee: publicAttendee(inserted), already: false };
  }

  // Ignored as a duplicate, which only a device hash can cause.
  let existing = null;
  if (row.device_hash) {
    existing = await findAttendeeByDevice(eventId, row.device_hash);
  }
  if (!existing) {
    throw databaseError(result);
  }
  return { attendee: publicAttendee(existing), already: true };
}

/** Name and note from an attendee, the note only if the event asks for one. */
export function attendeeFields(body, event) {
  const name = validate.text(body.name, "Your name", { minimum: 1, maximum: validate.LIMITS.name });
  let note = null;
  if (event.note_label) {
    note = validate.optionalText(body.note, event.note_label, { maximum: validate.LIMITS.note });
  }
  return { name, note };
}

// The value, or the fallback when the value is null or undefined.
function valueOrDefault(value, fallback) {
  if (value === null || value === undefined) {
    return fallback;
  }
  return value;
}

/**
 * Event settings from a request, as columns.
 *
 * Creating, every field gets a value. Updating, only the fields present in
 * the body are changed, and the result is checked against the row as it will
 * be, so a host cannot switch off both methods one request at a time.
 */
export function eventSettings(body, current = null) {
  const creating = current === null;
  // Whether this request sets the field: always when creating, and only when
  // the body names it when updating.
  const has = (key) => {
    return creating || Object.prototype.hasOwnProperty.call(body, key);
  };
  const columns = {};

  if (has("title")) {
    columns.title = validate.text(body.title, "The event name", { maximum: validate.LIMITS.title });
  }
  if (has("buttonLabel")) {
    columns.button_label = validate.text(valueOrDefault(body.buttonLabel, "I'm here"), "The button text", {
      minimum: 1,
      maximum: validate.LIMITS.buttonLabel,
    });
  }
  if (has("buttonColor")) {
    columns.button_color = validate.colour(valueOrDefault(body.buttonColor, "#ccffcc"));
  }
  if (has("noteLabel")) {
    columns.note_label = validate.optionalText(body.noteLabel, "The extra field name", { maximum: validate.LIMITS.noteLabel });
  }
  // Left out when creating, same wifi is on and location off, as in the
  // table's defaults and the form's.
  if (has("allowP2p")) {
    if (body.allowP2p === undefined) {
      columns.allow_p2p = creating;
    } else {
      columns.allow_p2p = validate.booleanValue(body.allowP2p);
    }
  }
  if (has("allowLocation")) {
    columns.allow_location = validate.booleanValue(body.allowLocation);
  }
  if (has("allowTap")) {
    columns.allow_tap = validate.booleanValue(body.allowTap);
  }
  if (has("allowBluetooth")) {
    columns.allow_bluetooth = validate.booleanValue(body.allowBluetooth);
  }
  if (has("radius")) {
    columns.radius_m = validate.radius(valueOrDefault(body.radius, 100));
  }

  if (body.location) {
    const hostPosition = validate.position(body.location);
    columns.host_lat = hostPosition.lat;
    columns.host_lng = hostPosition.lng;
    columns.host_accuracy_m = hostPosition.accuracy;
  }

  // The row as it will be once these columns are saved.
  let currentRow = current;
  if (currentRow === null || currentRow === undefined) {
    currentRow = {};
  }
  const merged = { ...currentRow, ...columns };
  if (!merged.allow_p2p && !merged.allow_location && !merged.allow_tap && !merged.allow_bluetooth) {
    throw new HttpError(422, "Pick at least one way for people to check in.", "invalid");
  }
  if (merged.allow_location && (merged.host_lat === null || merged.host_lat === undefined)) {
    throw new HttpError(
      422,
      "Location check-in needs this device's location. Allow location access, or switch it off.",
      "needs-location"
    );
  }

  return columns;
}
