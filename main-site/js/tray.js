// Edge tray (edge-tray-spec.md): the column of global actions pinned top
// right. Its tab slides the column off the right edge, leaving only the tab.
// Remembered per browser; open unless this browser last left it collapsed.

// Same key as the pre-paint script in every page's head. Change both together.
const TRAY_KEY = "uwuhere.trayOpen";

let tray;
let trayTab;
let trayButtons;

function setTray(open, { save = true } = {}) {
  tray.classList.toggle("collapsed", !open);
  trayTab.setAttribute("aria-expanded", String(open));
  trayTab.setAttribute("aria-label", open ? "Hide menu" : "Show menu");
  trayTab.title = open ? "Hide menu" : "Show menu";
  // Off-screen buttons must not take focus or clicks.
  trayButtons.inert = !open;
  document.body.classList.toggle("tray-open", open);
  if (save) {
    try {
      localStorage.setItem(TRAY_KEY, open ? "1" : "0");
    } catch {
      // Remembered for this page view only.
    }
  }
}

export function initTray() {
  tray = document.getElementById("tray");
  trayTab = document.getElementById("trayTab");
  trayButtons = document.getElementById("trayButtons");
  if (!tray || !trayTab || !trayButtons) return;

  let open = true;
  try {
    open = localStorage.getItem(TRAY_KEY) !== "0";
  } catch {
    // Open, the default.
  }
  setTray(open, { save: false });

  // The head script painted a stored collapse without transitions. Hand back
  // to the real state a frame later, so later toggles animate.
  requestAnimationFrame(() => {
    document.documentElement.classList.remove("tray-start-collapsed");
  });

  trayTab.addEventListener("click", () => setTray(tray.classList.contains("collapsed")));
}

// A sticky banner at the top (the update bar) publishes its height, so the
// tray starts below it and glides when it comes or goes (spec 6.3).
let sizer = null;

export function trackBanner(el) {
  sizer?.disconnect();
  sizer = null;
  if (!el) {
    document.documentElement.style.setProperty("--banner-h", "0px");
    return;
  }
  sizer = new ResizeObserver(([entry]) => {
    document.documentElement.style.setProperty("--banner-h", `${entry.target.offsetHeight}px`);
  });
  sizer.observe(el);
}
