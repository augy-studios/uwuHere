// Theme system: 7 brand colour swatches + light/dark mode.
// Default is always light + classic (#ccffcc), regardless of OS preference.
// Once the user picks something, it is persisted.

// Same key as the pre-paint script in every page's head. Change both together.
const APP_KEY = "uwuhere";

export const COLOR_THEMES = [
  { id: "classic", label: "Classic", hex: "#ccffcc" },
  { id: "not-green-1", label: "Not green 1", hex: "#ffcccc" },
  { id: "not-green-2", label: "Not green 2", hex: "#ccccff" },
  { id: "not-green-3", label: "Not green 3", hex: "#ffffcc" },
  { id: "not-green-4", label: "Not green 4", hex: "#ffccff" },
  { id: "not-green-5", label: "Not green 5", hex: "#ccffff" },
  { id: "really-light-green", label: "Really really light green", hex: "#ffffff" },
];

const STORAGE_KEY_COLOR = `${APP_KEY}.colorTheme`;
const STORAGE_KEY_MODE = `${APP_KEY}.mode`;

// "#ccffcc" as "204, 255, 204": the red, green and blue channels for CSS rgba().
function hexToRedGreenBlueText(hex) {
  const colourNumber = parseInt(hex.replace("#", ""), 16);
  const red = (colourNumber >> 16) & 255;
  const green = (colourNumber >> 8) & 255;
  const blue = colourNumber & 255;
  return `${red}, ${green}, ${blue}`;
}

export function getStoredColorTheme() {
  const storedTheme = localStorage.getItem(STORAGE_KEY_COLOR);
  if (storedTheme) {
    return storedTheme;
  }
  return "classic";
}

/* Mode preference and mode are different things. The preference is what the
   person chose and can be "time"; the mode is what the document is in and
   is only ever light or dark. */

export const MODE_PREFERENCES = ["light", "dark", "time"];

/* The daylight window. Duplicated in the pre-paint script in every head,
   which has to resolve this before first paint and cannot import anything.
   Change both together. */
export const LIGHT_FROM_HOUR = 9;
export const LIGHT_UNTIL_HOUR = 18;

export function getModePreference() {
  const storedPreference = localStorage.getItem(STORAGE_KEY_MODE);
  if (MODE_PREFERENCES.includes(storedPreference)) {
    return storedPreference;
  }
  return "light";
}

export function isDaylightHours(now = new Date()) {
  const hour = now.getHours();
  return hour >= LIGHT_FROM_HOUR && hour < LIGHT_UNTIL_HOUR;
}

export function resolveMode(preference) {
  if (preference === "time") {
    if (isDaylightHours()) {
      return "light";
    }
    return "dark";
  }
  if (preference === "dark") {
    return "dark";
  }
  return "light";
}

// The mode the document is in right now, resolved. What the theme button
// icon and anything else reading the active mode wants.
export function getStoredMode() {
  return resolveMode(getModePreference());
}

export function applyColorTheme(id) {
  let theme = COLOR_THEMES.find((candidate) => {
    return candidate.id === id;
  });
  if (!theme) {
    theme = COLOR_THEMES[0];
  }
  document.documentElement.setAttribute("data-color-theme", theme.id);
  document.documentElement.style.setProperty("--brand", theme.hex);
  document.documentElement.style.setProperty("--brand-rgb", hexToRedGreenBlueText(theme.hex));
  localStorage.setItem(STORAGE_KEY_COLOR, theme.id);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) {
    meta.setAttribute("content", theme.hex);
  }
  document.dispatchEvent(
    new CustomEvent("uwu:colorchange", { detail: { theme: theme.id } })
  );
  return theme;
}

export function applyMode(preference) {
  let chosen = "light";
  if (MODE_PREFERENCES.includes(preference)) {
    chosen = preference;
  }
  const resolved = resolveMode(chosen);

  document.documentElement.setAttribute("data-mode", resolved);
  document.documentElement.setAttribute("data-mode-preference", chosen);
  localStorage.setItem(STORAGE_KEY_MODE, chosen);

  scheduleModeCheck();

  return resolved;
}

/* Keeping the time based mode honest while the page stays open. */

let modeTimer = null;
let watchingVisibility = false;

// Milliseconds until the next 09:00 or 18:00, whichever comes first.
function millisecondsUntilNextBoundary(now = new Date()) {
  const next = new Date(now);
  next.setMinutes(0, 0, 0);

  const hour = now.getHours();
  if (hour < LIGHT_FROM_HOUR) {
    next.setHours(LIGHT_FROM_HOUR);
  } else if (hour < LIGHT_UNTIL_HOUR) {
    next.setHours(LIGHT_UNTIL_HOUR);
  } else {
    next.setDate(next.getDate() + 1);
    next.setHours(LIGHT_FROM_HOUR);
  }

  // A second of slack, so a timer that fires a fraction early does not land
  // back in the hour it just left and reschedule itself in a tight loop.
  return Math.max(1000, next.getTime() - now.getTime() + 1000);
}

function scheduleModeCheck() {
  if (modeTimer !== null) {
    clearTimeout(modeTimer);
    modeTimer = null;
  }

  if (getModePreference() !== "time") {
    return;
  }

  modeTimer = setTimeout(() => {
    modeTimer = null;
    refreshTimeMode();
  }, millisecondsUntilNextBoundary());

  if (!watchingVisibility && typeof document !== "undefined") {
    watchingVisibility = true;
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") {
        refreshTimeMode();
      }
    });
  }
}

export function refreshTimeMode() {
  if (getModePreference() !== "time") {
    return;
  }

  const resolved = resolveMode("time");
  const current = document.documentElement.getAttribute("data-mode");

  if (resolved !== current) {
    document.documentElement.setAttribute("data-mode", resolved);
    document.dispatchEvent(
      new CustomEvent("uwu:modechange", {
        detail: { mode: resolved, preference: "time" },
      })
    );
  }

  scheduleModeCheck();
}

export function initTheme() {
  applyColorTheme(getStoredColorTheme());
  // The preference, not the resolved mode. Passing the resolved one would
  // quietly rewrite a stored "time" into "dark" the first evening.
  applyMode(getModePreference());
}
