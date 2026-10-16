/* Host keys, passwords and device ids.

   **Host key.** Whoever holds it manages the event. It is an HMAC of the
   event id under UWUHERE_HOST_SECRET, so nothing has to be stored for it: the
   server recomputes it to check one. The browser that made the event keeps
   it, and a password, if the host set one, is the way to get it again on
   another device.

   **Password.** bcrypt, cost 12, over an HMAC of the password, which is the
   OWASP Password Storage Cheat Sheet's pattern when bcrypt is the hash:

     bcrypt(base64(HMAC-SHA384(password, pepper)), salt, cost)

   bcrypt reads at most 72 bytes and ignores the rest silently, and a host
   may type up to 128 characters. The HMAC makes every password a 64
   character base64 string, so all of it counts, with no NUL byte to cut it
   short. The pepper (UWUHERE_PASSWORD_PEPPER) lives in the environment, not
   the database, so a leaked table alone cannot be attacked offline. bcrypt
   gives each hash its own random salt. Never logged and never returned.

   **Device id.** A random id each attendee's browser makes once. Only its
   SHA-256 is stored, and only the hash is sent to the host over P2P, so the
   host cannot use it to act as the attendee (leaving early takes the raw id). */

import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import bcrypt from "bcryptjs";
import { HttpError } from "./http.js";

const SECRET = process.env.UWUHERE_HOST_SECRET || "";
const PEPPER = process.env.UWUHERE_PASSWORD_PEPPER || "";

// OWASP's floor is 10. 12 is a few hundred milliseconds in bcryptjs on a
// function: slow enough to make guessing expensive, quick enough that a host
// typing their password does not notice.
const BCRYPT_COST = 12;

export function requireHostSecret() {
  if (!SECRET) {
    throw new HttpError(503, "uwuHere is not configured on this deployment yet.", "unconfigured");
  }
}

export function hostKeyFor(eventId) {
  requireHostSecret();
  return createHmac("sha256", SECRET).update(`uwuhere-host:${eventId}`).digest("base64url");
}

export function isHostKey(eventId, given) {
  if (typeof given !== "string" || given.length === 0 || given.length > 128) return false;
  const expected = Buffer.from(hostKeyFor(eventId));
  const actual = Buffer.from(given);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function requirePepper() {
  if (!PEPPER) {
    throw new HttpError(503, "Event passwords are not configured on this deployment yet.", "unconfigured");
  }
}

// 48 bytes of HMAC, 64 characters of base64: under bcrypt's 72 byte limit,
// and free of the NUL byte that would end bcrypt's input early.
function peppered(password) {
  return createHmac("sha384", PEPPER).update(String(password).normalize("NFKC"), "utf8").digest("base64");
}

export async function hashPassword(password) {
  requirePepper();
  return bcrypt.hash(peppered(password), BCRYPT_COST);
}

export async function verifyPassword(password, stored) {
  requirePepper();
  if (typeof stored !== "string" || !/^\$2[aby]\$\d{2}\$/.test(stored)) return false;
  return bcrypt.compare(peppered(password), stored);
}

export function hashDevice(deviceId) {
  return createHash("sha256").update(deviceId).digest("hex");
}
