/* Input checks. Every value from a request passes through one of these before
   it reaches the database, and every limit here matches a check constraint in
   migrations/0001_uwuhere_tables.sql. Change both together. */

import { randomInt } from "node:crypto";
import { HttpError } from "./http.js";

// No vowels and no 0 O 1 I, so a code cannot spell a word or be misread.
// The same alphabet as js/p2p.js and the check on uwuhere_events.code.
export const CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXYZ23456789";
export const CODE_LENGTH = 6;

export const LIMITS = {
  title: 80,
  buttonLabel: 20,
  noteLabel: 40,
  name: 60,
  note: 120,
  // After NIST SP 800-63B-4, one under its 15. See _lib/password.js.
  passwordMin: 14,
  passwordMax: 128,
  radiusMin: 20,
  radiusMax: 2000,
};

export function generateCode() {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

export function normaliseCode(input) {
  return String(input || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, CODE_LENGTH);
}

export function requireCode(input) {
  const code = normaliseCode(input);
  if (code.length !== CODE_LENGTH || ![...code].every((c) => CODE_ALPHABET.includes(c))) {
    throw new HttpError(400, "That is not an event code.", "bad-code");
  }
  return code;
}

// Characters, counted the way Postgres char_length counts them: by code
// point, so an accented letter or a symbol counts once.
function length(value) {
  return [...value].length;
}

/**
 * A single line of text: whitespace collapsed, ends trimmed, control
 * characters removed. Too long is refused rather than cut, so nothing is
 * saved that differs from what the person typed.
 */
export function text(value, label, { min = 0, max }) {
  const clean = String(value ?? "")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (length(clean) < min) {
    throw new HttpError(422, min === 1 ? `${label} is required.` : `${label} needs at least ${min} characters.`, "invalid");
  }
  if (length(clean) > max) {
    throw new HttpError(422, `${label} can be at most ${max} characters.`, "invalid");
  }
  return clean;
}

/** Optional text: empty becomes null. */
export function optionalText(value, label, { max }) {
  const clean = text(value, label, { max });
  return clean === "" ? null : clean;
}

export function colour(value) {
  const match = /^#?([0-9a-fA-F]{6})$/.exec(String(value ?? "").trim());
  if (!match) throw new HttpError(422, "The button colour must be a colour like #ccffcc.", "invalid");
  return `#${match[1].toLowerCase()}`;
}

export function deviceId(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9-]{16,64}$/.test(value)) {
    throw new HttpError(400, "This browser's check-in id is missing. Reload and try again.", "bad-device");
  }
  return value;
}

export function deviceHash(value) {
  if (typeof value !== "string" || !/^[0-9a-f]{64}$/.test(value)) {
    throw new HttpError(422, "That check-in came without a device id.", "invalid");
  }
  return value;
}

export function uuid(value, label = "id") {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    throw new HttpError(400, `That ${label} is not valid.`, "invalid");
  }
  return value.toLowerCase();
}

export function password(value) {
  const clean = String(value ?? "");
  if (length(clean) < LIMITS.passwordMin || length(clean) > LIMITS.passwordMax) {
    throw new HttpError(
      422,
      `A password needs ${LIMITS.passwordMin} to ${LIMITS.passwordMax} characters.`,
      "invalid"
    );
  }
  return clean;
}

export function radius(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < LIMITS.radiusMin || n > LIMITS.radiusMax) {
    throw new HttpError(422, `The radius must be ${LIMITS.radiusMin} to ${LIMITS.radiusMax} metres.`, "invalid");
  }
  return n;
}

/** A position from the Geolocation API: { lat, lng, accuracy }. */
export function position(value) {
  const lat = Number(value?.lat);
  const lng = Number(value?.lng);
  const accuracy = Number(value?.accuracy);

  if (
    !Number.isFinite(lat) || lat < -90 || lat > 90 ||
    !Number.isFinite(lng) || lng < -180 || lng > 180 ||
    !Number.isFinite(accuracy) || accuracy < 0
  ) {
    throw new HttpError(422, "That location could not be read. Try again.", "bad-position");
  }
  return { lat, lng, accuracy };
}

export function bool(value) {
  return value === true;
}

/**
 * A time the client says something happened, for check-ins a host queued
 * while offline. Kept between the event's start and now, so a wrong clock
 * cannot put a check-in before the event existed or in the future.
 */
export function pastTime(value, notBefore) {
  const now = Date.now();
  const floor = Date.parse(notBefore);
  const at = Date.parse(value);
  if (!Number.isFinite(at)) return new Date(now).toISOString();
  return new Date(Math.min(now, Math.max(Number.isFinite(floor) ? floor : 0, at))).toISOString();
}
