import { icon } from "./icons.js";

// Safe to call repeatedly; re-renders when data-icon changes.
export function hydrateIcons(root = document) {
  root.querySelectorAll("[data-icon]").forEach((element) => {
    const name = element.dataset.icon;
    if (element.dataset.iconRendered === name) {
      return;
    }
    element.innerHTML = icon(name);
    element.dataset.iconRendered = name;
  });
}

// Where focus was before a modal opened, so closing it can hand focus back.
const returnFocus = new Map();

export function openModal(id) {
  const backdrop = document.getElementById(id);
  returnFocus.set(id, document.activeElement);
  backdrop.classList.remove("hidden");
  document.body.classList.add("modal-open");
  // Focus the first field, or failing that the first button.
  let elementToFocus = backdrop.querySelector("input, select, textarea, button:not([data-close-modal])");
  if (elementToFocus === null || elementToFocus === undefined) {
    elementToFocus = backdrop.querySelector("button");
  }
  if (elementToFocus !== null && elementToFocus !== undefined) {
    elementToFocus.focus({ preventScroll: true });
  }
}

export function closeModal(id) {
  document.getElementById(id).classList.add("hidden");
  if (!document.querySelector(".modal-backdrop:not(.hidden)")) {
    document.body.classList.remove("modal-open");
  }
  const previous = returnFocus.get(id);
  returnFocus.delete(id);
  if (previous && document.contains(previous)) {
    previous.focus({ preventScroll: true });
  }
  // However it was closed (its button, the backdrop, Escape), for a page that
  // has something to undo, such as the QR code's full brightness.
  document.dispatchEvent(new CustomEvent("uwu:modalclose", { detail: { id } }));
}

const HTML_ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => {
    return HTML_ESCAPES[character];
  });
}

// A short-lived line of feedback, for things like "Copied" that do not
// deserve a modal. One toast at a time; a second call replaces the first.
let toastTimer = null;
export function toast(message) {
  let toastElement = document.querySelector(".toast");
  if (!toastElement) {
    toastElement = document.createElement("div");
    toastElement.className = "toast hidden";
    toastElement.setAttribute("role", "status");
    document.body.appendChild(toastElement);
    // One frame in the hidden state first, so the first toast animates in.
    void toastElement.offsetWidth;
  }
  toastElement.textContent = message;
  toastElement.classList.remove("hidden");

  if (toastTimer) {
    clearTimeout(toastTimer);
  }
  toastTimer = setTimeout(() => {
    toastElement.classList.add("hidden");
    toastTimer = null;
  }, 2400);
}

export function formatTime(isoTimestamp) {
  if (!isoTimestamp) {
    return "";
  }
  return new Date(isoTimestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

export function formatDateTime(isoTimestamp) {
  if (!isoTimestamp) {
    return "";
  }
  return new Date(isoTimestamp).toLocaleString([], {
    day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
  });
}

// One colour channel (0 to 255) as linear light (0 to 1), the step the WCAG
// relative luminance formula needs.
function linearChannel(channelValue) {
  const scaled = channelValue / 255;
  if (scaled <= 0.03928) {
    return scaled / 12.92;
  }
  return ((scaled + 0.055) / 1.055) ** 2.4;
}

/**
 * Black or white text for a host-chosen colour, whichever contrasts more.
 * The button colour is data, not a theme token, so its text has to be worked
 * out rather than assumed: a host can pick navy as easily as pastel.
 */
export function inkFor(hex) {
  const colourNumber = parseInt(String(hex).replace("#", ""), 16);
  const red = (colourNumber >> 16) & 255;
  const green = (colourNumber >> 8) & 255;
  const blue = colourNumber & 255;
  const luminance = 0.2126 * linearChannel(red) + 0.7152 * linearChannel(green) + 0.0722 * linearChannel(blue);
  // Contrast against the theme's dark ink (#121815, luminance about 0.009)
  // and against white.
  const contrastWithDark = (luminance + 0.05) / (0.009 + 0.05);
  const contrastWithWhite = 1.05 / (luminance + 0.05);
  if (contrastWithDark >= contrastWithWhite) {
    return "#121815";
  }
  return "#ffffff";
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
  const originalMarkup = button.innerHTML;
  const originalLabel = button.getAttribute("aria-label");
  button.classList.add("confirming");
  button.textContent = prompt;
  button.setAttribute("aria-label", prompt);
  button.dataset.armTimer = String(
    setTimeout(() => {
      button.classList.remove("confirming");
      button.innerHTML = originalMarkup;
      if (originalLabel) {
        button.setAttribute("aria-label", originalLabel);
      }
    }, 3000)
  );
  return false;
}

/** Paints a .here-btn in an event's colour, with text that contrasts. */
export function paintHereButton(button, colour) {
  if (!/^#[0-9a-fA-F]{6}$/.test(String(colour))) {
    return;
  }
  button.style.setProperty("--event-color", colour);
  button.style.setProperty("--on-event", inkFor(colour));
}

/**
 * Font size for the big button's label. Up to 20 characters, the server's
 * limit, always fits the 280px circle: short labels read large, the longest
 * wrap onto two lines at the smallest size.
 */
export function hereLabelSize(label) {
  const labelLength = charCount(label);
  if (labelLength <= 8) {
    return "2.1rem";
  }
  if (labelLength <= 14) {
    return "1.7rem";
  }
  return "1.4rem";
}
