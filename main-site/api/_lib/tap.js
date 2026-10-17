/* Checking in by tapping phones.

   The host's phone, in the Android app, acts as an NFC tag
   (android/.../TapService.java). Each phone that touches it is handed a link
   to the join page with a token on the end, made fresh for that tap:

     https://here.uwuapps.org/join?id=CODE&tap=TIME.NONCE.MAC

     TIME   when the tap happened, in whole seconds since 1970
     NONCE  9 random bytes, 12 characters of base64url
     MAC    HMAC-SHA256 of "uwuhere-tap:CODE:TIME:NONCE" under the event's
            host key, its first 16 bytes in base64url (22 characters)

   Only a phone holding the host key can make one, and it needs no connection
   to do it: the server works the key out again from the event id (auth.js).

   **Once, and soon.** The nonce is stored with the check-in it made, and a
   unique index refuses it a second time. A token is good for TAP_TTL_S after
   the tap, so a link passed on to someone who isn't there is spent or stale
   by the time it could be used.

   **Or late, and marked so.** An attendee with no connection when they tap
   keeps the token in their browser and sends it with `late` once they have
   one (js/join.js). That's accepted for up to LATE_TTL_S, recorded at the
   tap's time as 'tap_late', which the host's list shows as "Tapped, sent
   later", so a link passed on and used hours afterwards can't pass as an
   ordinary tap. */

import { createHmac, timingSafeEqual } from "node:crypto";
import { hostKeyFor } from "./auth.js";
import { HttpError } from "./http.js";

// Long enough to type a name after tapping, short enough that a link sent to
// a friend outside goes stale.
export const TAP_TTL_S = 5 * 60;

// A tap kept by an attendee who was offline: long enough to get out of a
// venue with no signal and back online.
export const LATE_TTL_S = 12 * 60 * 60;

// The host's phone sets the time; its clock may run a little fast.
const CLOCK_SKEW_S = 2 * 60;

const TOKEN = /^(\d{9,11})\.([A-Za-z0-9_-]{12})\.([A-Za-z0-9_-]{22})$/;

function tapMac(eventId, code, time, nonce) {
  return createHmac("sha256", hostKeyFor(eventId))
    .update(`uwuhere-tap:${code}:${time}:${nonce}`)
    .digest()
    .subarray(0, 16);
}

/**
 * { nonce, at, late } if the token is the host's and recent enough: `at` is
 * when the tap happened, and `late` whether it's past TAP_TTL_S, which only
 * a request saying `late` is allowed. Throws otherwise.
 */
export function verifyTap(event, token, { late = false } = {}) {
  const match = TOKEN.exec(typeof token === "string" ? token : "");
  const again = "Tap your phone on the host's phone again.";
  if (!match) throw new HttpError(422, `That tap didn't come through whole. ${again}`, "tap-bad");

  const [, time, nonce, mac] = match;
  const given = Buffer.from(mac, "base64url");
  const expected = tapMac(event.id, event.code, time, nonce);
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) {
    throw new HttpError(403, `That tap isn't from this event's host. ${again}`, "tap-bad");
  }

  const age = Math.floor(Date.now() / 1000) - Number(time);
  const limit = late ? LATE_TTL_S : TAP_TTL_S;
  if (age > limit || age < -CLOCK_SKEW_S) {
    const ago = late ? `${LATE_TTL_S / 3600} hours` : `${TAP_TTL_S / 60} minutes`;
    throw new HttpError(403, `That tap was more than ${ago} ago. ${again}`, "tap-old");
  }
  return {
    nonce,
    at: new Date(Math.min(Date.now(), Number(time) * 1000)).toISOString(),
    late: age > TAP_TTL_S,
  };
}
