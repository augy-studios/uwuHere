// The live checklist under a host password field.
//
// Mirrors api/_lib/password.js, which has the final say: after NIST SP
// 800-63B-4, so 14 characters or more (one under NIST's 15, by choice), no
// rules about digits or symbols, and nothing predictable. The breach check only runs on
// the server, so here it is a promise rather than a tick. Change both
// together.

import { charCount, hydrateIcons, escapeHtml } from "./ui.js";

export const PASSWORD_MINIMUM_LENGTH = 14;
export const PASSWORD_MAXIMUM_LENGTH = 128;

// Rows of characters people type in order: the alphabet, digits, and the
// keyboard's rows and columns.
const KEYBOARD_RUNS = [
  "abcdefghijklmnopqrstuvwxyz",
  "0123456789",
  "qwertyuiop",
  "asdfghjkl",
  "zxcvbnm",
  "qwertyuiopasdfghjklzxcvbnm",
  "1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik9ol0p",
];

// Lower case, normalised, with everything but letters and digits taken out.
function squash(text) {
  return String(text).toLowerCase().normalize("NFKC").replace(/[^\p{L}\p{N}]/gu, "");
}

// Whether the text is one short chunk said over and over, such as "abcabcabc".
function isRepeat(text) {
  return /^(.{1,6}?)\1+.{0,6}$/u.test(text);
}

// Whether the text is a stretch of one of the keyboard runs, forwards or
// backwards, wrapping round the end of the run.
function isRun(text) {
  if (text.length < 4) {
    return false;
  }
  return KEYBOARD_RUNS.some((run) => {
    const repeatedRun = run.repeat(Math.ceil((text.length * 2) / run.length) + 2);
    const reversedRun = [...repeatedRun].reverse().join("");
    return repeatedRun.includes(text) || reversedRun.includes(text);
  });
}

// The sentence for the length check, with how many characters so far when short.
function describeLengthRule(length) {
  if (length > PASSWORD_MAXIMUM_LENGTH) {
    return `At most ${PASSWORD_MAXIMUM_LENGTH} characters`;
  }
  let soFar = "";
  if (length < PASSWORD_MINIMUM_LENGTH) {
    soFar = ` (${length} so far)`;
  }
  return `${PASSWORD_MINIMUM_LENGTH} characters or more${soFar}`;
}

// Runs every rule over the password: { ok, checks: [{ ok, text }] }.
export function checkPassword(password, { title = "", code = "" } = {}) {
  const length = charCount(password);
  const plain = squash(password);
  const ownWords = ["uwuhere", squash(title), squash(code)].filter((word) => {
    return word.length >= 4;
  });
  const typed = length > 0;

  const checks = [
    {
      ok: length >= PASSWORD_MINIMUM_LENGTH && length <= PASSWORD_MAXIMUM_LENGTH,
      text: describeLengthRule(length),
    },
    { ok: typed && !isRepeat(plain) && !isRun(plain), text: "Not a repeat or a run like 12345 or qwerty" },
    {
      ok:
        typed &&
        !ownWords.some((word) => {
          return plain.includes(word);
        }),
      text: "Leaves out the event's name and code",
    },
  ];

  const allPassed = checks.every((check) => {
    return check.ok;
  });
  return { ok: allPassed, checks };
}

// One line of the checklist: a tick or a cross, and the rule.
function renderCheckItem(check) {
  let itemClass = "";
  let iconName = "close";
  let spokenState = ", not yet";
  if (check.ok) {
    itemClass = "ok";
    iconName = "check";
    spokenState = ", done";
  }
  return `
        <li class="${itemClass}">
          <span data-icon="${iconName}"></span>
          <span>${escapeHtml(check.text)}<span class="visually-hidden">${spokenState}</span></span>
        </li>`;
}

/** Draws the checklist into a <ul>. Hidden while the field is empty. */
export function renderPasswordChecks(list, password, context) {
  list.hidden = password.length === 0;
  if (list.hidden) {
    return checkPassword(password, context);
  }

  const result = checkPassword(password, context);
  list.innerHTML =
    result.checks.map(renderCheckItem).join("") +
    `<li class="later"><span data-icon="lock"></span><span>Checked against known data breaches when you save</span></li>`;
  hydrateIcons(list);
  return result;
}
