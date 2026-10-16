// The home page: join by code, make an event, and the events this browser
// hosts.

import { bootShell } from "./shell.js";
import { postJson } from "./api.js";
import { getPosition } from "./geo.js";
import { normaliseCode, isValidCode } from "./p2p.js";
import { saveHosted, saveHostCache, listHosted, forgetHosted } from "./store.js";
import { checkPassword, renderPasswordChecks } from "./password.js";
import { escapeHtml, formatDateTime, charCount, paintHereButton, hydrateIcons, armed } from "./ui.js";

bootShell();

const $ = (id) => document.getElementById(id);

/* ---- join, and open an event you host ---- */

// A code box that goes to `page`?id=CODE. Used to join as an attendee, and to
// reach the host page from a device that did not make the event.
function codeForm(formId, inputId, errorId, page) {
  $(inputId).addEventListener("input", (e) => {
    const caret = e.target.selectionStart;
    e.target.value = e.target.value.toUpperCase();
    e.target.setSelectionRange(caret, caret);
    $(errorId).hidden = true;
  });

  $(formId).addEventListener("submit", (e) => {
    e.preventDefault();
    const code = normaliseCode($(inputId).value);
    if (!isValidCode(code)) {
      $(errorId).textContent = "An event code is 6 letters and numbers, like BCD234.";
      $(errorId).hidden = false;
      return;
    }
    location.href = `${page}?id=${code}`;
  });
}

codeForm("joinForm", "joinCode", "joinError", "/join");
codeForm("openForm", "openCode", "openError", "/host");

/* ---- create ---- */

const LIMITS = { title: 80, buttonLabel: 20, noteLabel: 40 };
const methods = { p2p: true, location: false };

function counter(inputId, countId, max) {
  const input = $(inputId);
  const out = $(countId);
  const update = () => {
    const n = charCount(input.value);
    out.textContent = `${n}/${max}`;
    out.classList.toggle("full", n >= max);
  };
  input.addEventListener("input", update);
  update();
}

counter("title", "titleCount", LIMITS.title);
counter("buttonLabel", "labelCount", LIMITS.buttonLabel);
counter("noteLabel", "noteCount", LIMITS.noteLabel);

function updatePreview() {
  $("previewLabel").textContent = $("buttonLabel").value.trim() || "I'm here";
  paintHereButton($("preview"), $("buttonColor").value);
}
$("buttonLabel").addEventListener("input", updatePreview);
$("buttonColor").addEventListener("input", updatePreview);
updatePreview();

function renderMethods() {
  document.querySelectorAll("#methods [data-method]").forEach((btn) => {
    btn.setAttribute("aria-pressed", String(methods[btn.dataset.method]));
  });
  $("radiusField").hidden = !methods.location;

  const hints = [];
  if (methods.p2p) {
    hints.push("Same wifi: attendees' phones connect to this screen directly, so keep this page open.");
  }
  if (methods.location) {
    hints.push("Location: attendees share their location once and must be near where you are now.");
  }
  $("methodHint").textContent = hints.join(" ") || "Pick at least one.";
}

$("methods").addEventListener("click", (e) => {
  const btn = e.target.closest("[data-method]");
  if (!btn) return;
  methods[btn.dataset.method] = !methods[btn.dataset.method];
  renderMethods();
});
renderMethods();

function updatePasswordChecks() {
  renderPasswordChecks($("pwChecks"), $("password").value, { title: $("title").value });
}
$("password").addEventListener("input", updatePasswordChecks);
$("title").addEventListener("input", updatePasswordChecks);

function showCreateError(message) {
  $("createError").textContent = message;
  $("createError").hidden = !message;
}

$("createForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  showCreateError("");

  const buttonLabel = $("buttonLabel").value.trim();
  const password = $("password").value;

  if (!buttonLabel) return showCreateError("The button needs some text.");
  if (charCount(buttonLabel) > LIMITS.buttonLabel) {
    return showCreateError(`The button text can be at most ${LIMITS.buttonLabel} characters.`);
  }
  if (!methods.p2p && !methods.location) return showCreateError("Pick at least one way for people to check in.");
  if (password && !checkPassword(password, { title: $("title").value }).ok) {
    $("password").focus();
    return showCreateError("That password is not strong enough yet. See the checklist under it.");
  }

  const button = $("createBtn");
  button.disabled = true;

  try {
    let position = null;
    if (methods.location) {
      button.lastChild.textContent = "Finding your location";
      try {
        position = await getPosition();
      } catch (cause) {
        return showCreateError(cause.message);
      }
    }

    button.lastChild.textContent = "Creating";
    const result = await postJson("events", {
      title: $("title").value,
      buttonLabel,
      buttonColor: $("buttonColor").value,
      noteLabel: $("noteLabel").value,
      allowP2p: methods.p2p,
      allowLocation: methods.location,
      radius: Number($("radius").value),
      location: position,
      password: password || undefined,
    });

    if (!result.ok) {
      return showCreateError(result.offline ? "Making an event needs a connection." : result.error);
    }

    const { code, hostKey, event, attendees } = result.data;
    saveHosted(code, hostKey, event);
    saveHostCache(code, { event, attendees });
    location.href = `/host?id=${code}`;
  } finally {
    button.disabled = false;
    button.lastChild.textContent = "Create event";
  }
});

/* ---- your events ---- */

function renderHosted() {
  const events = listHosted();
  $("hostedList").hidden = events.length === 0;

  $("hostedList").innerHTML = events
    .map(
      (ev) => `
      <li class="hosted-row">
        <a href="/host?id=${ev.code}">
          <span class="hosted-title">${escapeHtml(ev.title || "Untitled event")}</span>
          <span class="hosted-meta">${ev.code} &middot; ${escapeHtml(formatDateTime(ev.createdAt))}${ev.ended ? " &middot; Ended" : ""}</span>
        </a>
        <button class="icon-btn small remove-btn" type="button" data-forget="${ev.code}"
          aria-label="Forget ${ev.code} on this device. Without a password you cannot get it back."
          title="Forget on this device">
          <span data-icon="close"></span>
        </button>
      </li>`
    )
    .join("");
  hydrateIcons($("hostedList"));
}

$("hostedList").addEventListener("click", (e) => {
  const btn = e.target.closest("[data-forget]");
  if (!btn || !armed(btn, "Forget?")) return;
  forgetHosted(btn.dataset.forget);
  renderHosted();
});

renderHosted();
