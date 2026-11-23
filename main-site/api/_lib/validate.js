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
  passwordMinimum: 14,
  passwordMaximum: 128,
  radiusMinimum: 20,
  radiusMaximum: 2000,
};

export function generateCode() {
  let code = "";
  for (let index = 0; index < CODE_LENGTH; index = index + 1) {
    code = code + CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  }
  return code;
}

export function normaliseCode(input) {
  let text = input;
  if (!text) {
    text = "";
  }
  return String(text).toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, CODE_LENGTH);
}

export function requireCode(input) {
  const code = normaliseCode(input);
  const everyCharacterAllowed = [...code].every((character) => {
    return CODE_ALPHABET.includes(character);
  });
  if (code.length !== CODE_LENGTH || !everyCharacterAllowed) {
    throw new HttpError(400, "That is not an event code.", "bad-code");
  }
  return code;
}

// Characters, counted the way Postgres char_length counts them: by code
// point, so an accented letter or a symbol counts once.
function characterCount(value) {
  return [...value].length;
}

// The value as a string, with null and undefined becoming "".
function stringOrEmpty(value) {
  if (value === null || value === undefined) {
    return "";
  }
  return String(value);
}

/**
 * A single line of text: whitespace collapsed, ends trimmed, control
 * characters removed. Too long is refused rather than cut, so nothing is
 * saved that differs from what the person typed.
 */
export function text(value, label, { minimum = 0, maximum }) {
  const clean = stringOrEmpty(value)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (characterCount(clean) < minimum) {
    let sentence;
    if (minimum === 1) {
      sentence = `${label} is required.`;
    } else {
      sentence = `${label} needs at least ${minimum} characters.`;
    }
    throw new HttpError(422, sentence, "invalid");
  }
  if (characterCount(clean) > maximum) {
    throw new HttpError(422, `${label} can be at most ${maximum} characters.`, "invalid");
  }
  return clean;
}

/** Optional text: empty becomes null. */
export function optionalText(value, label, { maximum }) {
  const clean = text(value, label, { maximum });
  if (clean === "") {
    return null;
  }
  return clean;
}

export function colour(value) {
  const match = /^#?([0-9a-fA-F]{6})$/.exec(stringOrEmpty(value).trim());
  if (!match) {
    throw new HttpError(422, "The button colour must be a colour like #ccffcc.", "invalid");
  }
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
  const clean = stringOrEmpty(value);
  if (characterCount(clean) < LIMITS.passwordMinimum || characterCount(clean) > LIMITS.passwordMaximum) {
    throw new HttpError(
      422,
      `A password needs ${LIMITS.passwordMinimum} to ${LIMITS.passwordMaximum} characters.`,
      "invalid"
    );
  }
  return clean;
}

export function radius(value) {
  const metres = Number(value);
  if (!Number.isInteger(metres) || metres < LIMITS.radiusMinimum || metres > LIMITS.radiusMaximum) {
    throw new HttpError(422, `The radius must be ${LIMITS.radiusMinimum} to ${LIMITS.radiusMaximum} metres.`, "invalid");
  }
  return metres;
}

// One field of an object that may itself be null or undefined, as a number.
function numberField(value, fieldName) {
  if (value === null || value === undefined) {
    return Number(undefined);
  }
  return Number(value[fieldName]);
}

/** A position from the Geolocation API: { lat, lng, accuracy }. */
export function position(value) {
  const latitude = numberField(value, "lat");
  const longitude = numberField(value, "lng");
  const accuracy = numberField(value, "accuracy");

  if (
    !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
    !Number.isFinite(longitude) || longitude < -180 || longitude > 180 ||
    !Number.isFinite(accuracy) || accuracy < 0
  ) {
    throw new HttpError(422, "That location could not be read. Try again.", "bad-position");
  }
  return { lat: latitude, lng: longitude, accuracy };
}

export function booleanValue(value) {
  return value === true;
}

/**
 * A time the client says something happened, for check-ins a host queued
 * while offline. Kept between the event's start and now, so a wrong clock
 * cannot put a check-in before the event existed or in the future.
 */
export function pastTime(value, notBefore) {
  const now = Date.now();
  const earliestTime = Date.parse(notBefore);
  const claimedTime = Date.parse(value);
  if (!Number.isFinite(claimedTime)) {
    return new Date(now).toISOString();
  }
  let lowerBound = 0;
  if (Number.isFinite(earliestTime)) {
    lowerBound = earliestTime;
  }
  return new Date(Math.min(now, Math.max(lowerBound, claimedTime))).toISOString();
}
