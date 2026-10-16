import { icon } from "./icons.js";

// Safe to call repeatedly; re-renders when data-icon changes.
export function hydrateIcons(root = document) {
  root.querySelectorAll("[data-icon]").forEach((el) => {
    const name = el.dataset.icon;
    if (el.dataset.iconRendered === name) return;
    el.innerHTML = icon(name);
    el.dataset.iconRendered = name;
  });
}

// Where focus was before a modal opened, so closing it can hand focus back.
const returnFocus = new Map();

export function openModal(id) {
  const backdrop = document.getElementById(id);
  returnFocus.set(id, document.activeElement);
  backdrop.classList.remove("hidden");
  document.body.classList.add("modal-open");
  const first = backdrop.querySelector("input, select, textarea, button:not([data-close-modal])");
  (first ?? backdrop.querySelector("button"))?.focus({ preventScroll: true });
}

export function closeModal(id) {
  document.getElementById(id).classList.add("hidden");
  if (!document.querySelector(".modal-backdrop:not(.hidden)")) {
    document.body.classList.remove("modal-open");
  }
  const previous = returnFocus.get(id);
  returnFocus.delete(id);
  if (previous && document.contains(previous)) previous.focus({ preventScroll: true });
}

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
  });
}

// A short-lived line of feedback, for things like "Copied" that do not
// deserve a modal. One toast at a time; a second call replaces the first.
let toastTimer = null;
export function toast(message) {
  let el = document.querySelector(".toast");
  if (!el) {
    el = document.createElement("div");
    el.className = "toast hidden";
    el.setAttribute("role", "status");
    document.body.appendChild(el);
    // One frame in the hidden state first, so the first toast animates in.
    void el.offsetWidth;
  }
  el.textContent = message;
  el.classList.remove("hidden");

  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    el.classList.add("hidden");
    toastTimer = null;
  }, 2400);
}

export function formatTime(iso) {
  if (!iso) return "";
  return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

export function formatDateTime(iso) {
  if (!iso) return "";
  return new Date(iso).toLocaleString([], {
    day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
  });
}

/**
 * Black or white text for a host-chosen colour, whichever contrasts more.
 * The button colour is data, not a theme token, so its text has to be worked
 * out rather than assumed: a host can pick navy as easily as pastel.
 */
export function inkFor(hex) {
  const n = parseInt(String(hex).replace("#", ""), 16);
  const channel = (c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  const lum = 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255);
  // Contrast against the theme's dark ink (#121815, luminance about 0.009)
  // and against white.
  const withDark = (lum + 0.05) / (0.009 + 0.05);
  const withWhite = 1.05 / (lum + 0.05);
  return withDark >= withWhite ? "#121815" : "#ffffff";
}

/** Code points, the way the server and the database count a limit. */
export function charCount(value) {
  return [...String(value)].length;
}

/**
 * Two taps for something that cannot be undone. The first arms the button,
 * which says what the second tap will do; the second, within three seconds,
 * returns true. Lighter than a modal for a row in a list.
 */
export function armed(button, prompt) {
  if (button.classList.contains("confirming")) {
    clearTimeout(Number(button.dataset.armTimer));
    return true;
  }
  const original = button.innerHTML;
  const label = button.getAttribute("aria-label");
  button.classList.add("confirming");
  button.textContent = prompt;
  button.setAttribute("aria-label", prompt);
  button.dataset.armTimer = String(
    setTimeout(() => {
      button.classList.remove("confirming");
      button.innerHTML = original;
      if (label) button.setAttribute("aria-label", label);
    }, 3000)
  );
  return false;
}

/** Paints a .here-btn in an event's colour, with text that contrasts. */
export function paintHereButton(button, colour) {
  if (!/^#[0-9a-fA-F]{6}$/.test(String(colour))) return;
  button.style.setProperty("--event-color", colour);
  button.style.setProperty("--on-event", inkFor(colour));
}

/**
 * Font size for the big button's label. Up to 20 characters, the server's
 * limit, always fits the 280px circle: short labels read large, the longest
 * wrap onto two lines at the smallest size.
 */
export function hereLabelSize(label) {
  const n = charCount(label);
  if (n <= 8) return "2.1rem";
  if (n <= 14) return "1.7rem";
  return "1.4rem";
}
