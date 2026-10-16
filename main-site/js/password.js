// The live checklist under a host password field.
//
// Mirrors api/_lib/password.js, which has the final say: after NIST SP
// 800-63B-4, so 14 characters or more (one under NIST's 15, by choice), no
// rules about digits or symbols, and nothing predictable. The breach check only runs on
// the server, so here it is a promise rather than a tick. Change both
// together.

import { charCount, hydrateIcons, escapeHtml } from "./ui.js";

export const PASSWORD_MIN = 14;
export const PASSWORD_MAX = 128;

const RUNS = [
  "abcdefghijklmnopqrstuvwxyz",
  "0123456789",
  "qwertyuiop",
  "asdfghjkl",
  "zxcvbnm",
  "qwertyuiopasdfghjklzxcvbnm",
  "1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik9ol0p",
];

function squash(text) {
  return String(text).toLowerCase().normalize("NFKC").replace(/[^\p{L}\p{N}]/gu, "");
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

export function checkPassword(password, { title = "", code = "" } = {}) {
  const length = charCount(password);
  const plain = squash(password);
  const own = ["uwuhere", squash(title), squash(code)].filter((word) => word.length >= 4);
  const typed = length > 0;

  const checks = [
    {
      ok: length >= PASSWORD_MIN && length <= PASSWORD_MAX,
      text:
        length > PASSWORD_MAX
          ? `At most ${PASSWORD_MAX} characters`
          : `${PASSWORD_MIN} characters or more${length < PASSWORD_MIN ? ` (${length} so far)` : ""}`,
    },
    { ok: typed && !isRepeat(plain) && !isRun(plain), text: "Not a repeat or a run like 12345 or qwerty" },
    { ok: typed && !own.some((word) => plain.includes(word)), text: "Leaves out the event's name and code" },
  ];

  return { ok: checks.every((c) => c.ok), checks };
}

/** Draws the checklist into a <ul>. Hidden while the field is empty. */
export function renderPasswordChecks(list, password, context) {
  list.hidden = password.length === 0;
  if (list.hidden) return checkPassword(password, context);

  const result = checkPassword(password, context);
  list.innerHTML =
    result.checks
      .map(
        (c) => `
        <li class="${c.ok ? "ok" : ""}">
          <span data-icon="${c.ok ? "check" : "close"}"></span>
          <span>${escapeHtml(c.text)}<span class="visually-hidden">${c.ok ? ", done" : ", not yet"}</span></span>
        </li>`
      )
      .join("") +
    `<li class="later"><span data-icon="lock"></span><span>Checked against known data breaches when you save</span></li>`;
  hydrateIcons(list);
  return result;
}
