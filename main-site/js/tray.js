// Edge tray (edge-tray-spec.md): the column of global actions pinned top
// right. Its tab slides the column off the right edge, leaving only the tab.
// Remembered per browser; open unless this browser last left it collapsed.

// Same key as the pre-paint script in every page's head. Change both together.
const TRAY_STORAGE_KEY = "uwuhere.trayOpen";

let tray;
let trayTab;
let trayButtons;

// Opens or collapses the tray, keeping its tab's labels, focus rules and the
// body class in step, and remembers the choice unless told not to.
function setTray(open, { save = true } = {}) {
  let tabLabel;
  if (open) {
    tabLabel = "Hide menu";
  } else {
    tabLabel = "Show menu";
  }

  tray.classList.toggle("collapsed", !open);
  trayTab.setAttribute("aria-expanded", String(open));
  trayTab.setAttribute("aria-label", tabLabel);
  trayTab.title = tabLabel;
  // Off-screen buttons must not take focus or clicks.
  trayButtons.inert = !open;
  document.body.classList.toggle("tray-open", open);
  if (save) {
    let storedValue;
    if (open) {
      storedValue = "1";
    } else {
      storedValue = "0";
    }
    try {
      localStorage.setItem(TRAY_STORAGE_KEY, storedValue);
    } catch {
      // Remembered for this page view only.
    }
  }
}

export function initTray() {
  tray = document.getElementById("tray");
  trayTab = document.getElementById("trayTab");
  trayButtons = document.getElementById("trayButtons");
  if (!tray || !trayTab || !trayButtons) {
    return;
  }

  let open = true;
  try {
    open = localStorage.getItem(TRAY_STORAGE_KEY) !== "0";
  } catch {
    // Open, the default.
  }
  setTray(open, { save: false });

  // The head script painted a stored collapse without transitions. Hand back
  // to the real state a frame later, so later toggles animate.
  requestAnimationFrame(() => {
    document.documentElement.classList.remove("tray-start-collapsed");
  });

  trayTab.addEventListener("click", () => {
    setTray(tray.classList.contains("collapsed"));
  });
}

/**
 * A button the Android app adds to the tray (js/app-update.js,
 * js/app-notify.js), just above the theme button, with the global actions.
 * Made here rather than shipped hidden in each page, as the website and the
 * PWA never show them.
 */
export function addTrayButton({ id, icon, label, onClick }) {
  const themeButton = document.getElementById("themeBtn");
  if (!themeButton || document.getElementById(id)) {
    return null;
  }
  const button = document.createElement("button");
  button.id = id;
  button.className = "glass-btn";
  button.type = "button";
  button.setAttribute("aria-label", label);
  button.title = label;
  button.innerHTML = `<span data-icon="${icon}"></span>`;
  button.addEventListener("click", onClick);
  themeButton.before(button);
  return button;
}

// A sticky banner at the top (the update bar) publishes its height, so the
// tray starts below it and glides when it comes or goes (spec 6.3).
let bannerResizeObserver = null;

export function trackBanner(banner) {
  if (bannerResizeObserver !== null && bannerResizeObserver !== undefined) {
    bannerResizeObserver.disconnect();
  }
  bannerResizeObserver = null;
  if (!banner) {
    document.documentElement.style.setProperty("--banner-h", "0px");
    return;
  }
  bannerResizeObserver = new ResizeObserver(([entry]) => {
    document.documentElement.style.setProperty("--banner-h", `${entry.target.offsetHeight}px`);
  });
  bannerResizeObserver.observe(banner);
}
