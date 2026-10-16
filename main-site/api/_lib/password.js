/* The host password policy, after NIST SP 800-63B-4 (August 2025).

   The password is the only thing guarding an event's host page from another
   device, so it is a single-factor password, and the rules for those apply:

     - At least 15 characters. Up to 128, past NIST's 64 floor.
     - No composition rules. NIST says they SHALL NOT be imposed: forcing a
       digit and a symbol produces "Password1!", not strength.
     - Refused if it is on a blocklist of common, expected, or compromised
       values. Here that is three checks: a repeat or a keyboard or alphabet
       run, the event's own name or code or the app's name, and the Have I
       Been Pwned breach corpus.

   The breach check uses HIBP's k-anonymity range API: only the first five hex
   characters of the SHA-1 leave this function, never the password or its
   whole hash. If HIBP cannot be reached the check is skipped rather than
   blocking the host, and the other rules still apply.

   js/password.js mirrors the first two checks for the live checklist under
   the field. Change both together. */

import { createHash } from "node:crypto";
import { HttpError } from "./http.js";
import * as v from "./validate.js";

const RUNS = [
  "abcdefghijklmnopqrstuvwxyz",
  "0123456789",
  "qwertyuiop",
  "asdfghjkl",
  "zxcvbnm",
  "qwertyuiopasdfghjklzxcvbnm",
  "1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik9ol0p",
];

/** Lowercase, and only letters and digits, for pattern checks. */
function squash(text) {
  return text.toLowerCase().normalize("NFKC").replace(/[^\p{L}\p{N}]/gu, "");
}

function isRepeat(text) {
  return /^(.{1,6}?)\1+.{0,6}$/u.test(text);
}

function isRun(text) {
  if (text.length < 4) return false;
  return RUNS.some((run) => {
    const loop = run.repeat(Math.ceil((text.length * 2) / run.length) + 2);
    const back = [...loop].reverse().join("");
    return loop.includes(text) || back.includes(text);
  });
}

/**
 * Throws a 422 with a sentence for the host if the password is not good
 * enough; returns it otherwise. `context` is the event's own words.
 */
export async function checkHostPassword(input, { title = "", code = "" } = {}) {
  const password = v.password(input);
  const plain = squash(password);

  if (isRepeat(plain) || isRun(plain)) {
    throw new HttpError(422, "That password is a repeat or a run of keys. Pick something less predictable.", "weak-password");
  }

  const own = ["uwuhere", squash(title), squash(code)].filter((word) => word.length >= 4);
  if (own.some((word) => plain.includes(word))) {
    throw new HttpError(422, "Leave the event's name and code out of its password.", "weak-password");
  }

  if (await isBreached(password)) {
    throw new HttpError(
      422,
      "That password has appeared in a known data breach, so it is on attackers' lists. Pick another.",
      "breached-password"
    );
  }

  return password;
}

async function isBreached(password) {
  const sha1 = createHash("sha1").update(password, "utf8").digest("hex").toUpperCase();
  const prefix = sha1.slice(0, 5);
  const suffix = sha1.slice(5);

  try {
    const response = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`, {
      headers: { "User-Agent": "uwuHere (here.uwuapps.org)", "Add-Padding": "true" },
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) throw new Error(`HIBP answered ${response.status}`);

    const body = await response.text();
    return body.split("\n").some((line) => {
      const [hash, count] = line.trim().split(":");
      // Padding entries carry a count of 0.
      return hash === suffix && Number(count) > 0;
    });
  } catch (cause) {
    console.warn("[uwuhere] breach check skipped:", cause?.message ?? cause);
    return false;
  }
}
