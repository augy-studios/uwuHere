/* Reading and shaping events and attendees.

   The database speaks snake_case and the client camelCase. The two view
   functions here are the only places a row is turned into something sent
   to a browser, so a column that must never leave the server, such as
   password_hash or device_hash, is left out in exactly one place. */

import { rest } from "./supabase.js";
import { HttpError, dbError } from "./http.js";
import * as v from "./validate.js";

const EVENT_COLUMNS = [
  "id", "code", "title", "button_label", "button_color", "note_label",
  "allow_p2p", "allow_location", "allow_tap", "host_lat", "host_lng", "host_accuracy_m",
  "radius_m", "password_hash", "paused", "created_at", "ended_at",
].join(",");

const ATTENDEE_COLUMNS = "id,name,note,method,distance_m,checked_in_at,left_early_at";

export async function findEvent(code) {
  const result = await rest("uwuhere_events", {
    query: { code: `eq.${code}`, select: EVENT_COLUMNS, limit: "1" },
  });
  if (!result.ok) throw dbError(result);
  return result.data?.[0] ?? null;
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
    hasLocation: row.host_lat !== null,
    radius: row.radius_m,
    paused: row.paused,
    createdAt: row.created_at,
    ended: row.ended_at !== null,
    endedAt: row.ended_at,
  };
}

/** What the host sees: everything public, and whether a password is set. */
export function hostEvent(row) {
  return {
    ...publicEvent(row),
    hasPassword: Boolean(row.password_hash),
    location:
      row.host_lat === null
        ? null
        : { lat: row.host_lat, lng: row.host_lng, accuracy: row.host_accuracy_m },
  };
}

export function publicAttendee(row) {
  return {
    id: row.id,
    name: row.name,
    note: row.note,
    method: row.method,
    distance: row.distance_m === null ? null : Math.round(row.distance_m),
    checkedInAt: row.checked_in_at,
    leftEarlyAt: row.left_early_at,
  };
}

export async function listAttendees(eventId) {
  const result = await rest("uwuhere_attendees", {
    query: { event_id: `eq.${eventId}`, select: ATTENDEE_COLUMNS, order: "checked_in_at.asc" },
  });
  if (!result.ok) throw dbError(result);
  return (result.data ?? []).map(publicAttendee);
}

export async function findAttendeeByDevice(eventId, hash) {
  const result = await rest("uwuhere_attendees", {
    query: { event_id: `eq.${eventId}`, device_hash: `eq.${hash}`, select: ATTENDEE_COLUMNS, limit: "1" },
  });
  if (!result.ok) throw dbError(result);
  return result.data?.[0] ?? null;
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
  if (!result.ok) throw dbError(result);

  const inserted = result.data?.[0];
  if (inserted) return { attendee: publicAttendee(inserted), already: false };

  // Ignored as a duplicate, which only a device hash can cause.
  const existing = row.device_hash ? await findAttendeeByDevice(eventId, row.device_hash) : null;
  if (!existing) throw dbError(result);
  return { attendee: publicAttendee(existing), already: true };
}

/** Name and note from an attendee, the note only if the event asks for one. */
export function attendeeFields(body, event) {
  return {
    name: v.text(body.name, "Your name", { min: 1, max: v.LIMITS.name }),
    note: event.note_label ? v.optionalText(body.note, event.note_label, { max: v.LIMITS.note }) : null,
  };
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
  const has = (key) => creating || Object.prototype.hasOwnProperty.call(body, key);
  const columns = {};

  if (has("title")) columns.title = v.text(body.title, "The event name", { max: v.LIMITS.title });
  if (has("buttonLabel")) {
    columns.button_label = v.text(body.buttonLabel ?? "I'm here", "The button text", {
      min: 1,
      max: v.LIMITS.buttonLabel,
    });
  }
  if (has("buttonColor")) columns.button_color = v.colour(body.buttonColor ?? "#ccffcc");
  if (has("noteLabel")) columns.note_label = v.optionalText(body.noteLabel, "The extra field name", { max: v.LIMITS.noteLabel });
  // Left out when creating, same wifi is on and location off, as in the
  // table's defaults and the form's.
  if (has("allowP2p")) columns.allow_p2p = body.allowP2p === undefined ? creating : v.bool(body.allowP2p);
  if (has("allowLocation")) columns.allow_location = v.bool(body.allowLocation);
  if (has("allowTap")) columns.allow_tap = v.bool(body.allowTap);
  if (has("radius")) columns.radius_m = v.radius(body.radius ?? 100);

  if (body.location) {
    const at = v.position(body.location);
    columns.host_lat = at.lat;
    columns.host_lng = at.lng;
    columns.host_accuracy_m = at.accuracy;
  }

  const merged = { ...(current ?? {}), ...columns };
  if (!merged.allow_p2p && !merged.allow_location && !merged.allow_tap) {
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
