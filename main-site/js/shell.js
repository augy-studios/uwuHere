// What every page shares: the theme and its modal (uwuapps-theme.md section
// 6), the icons, the edge tray, modal closing, the update bar, Report a bug
// and the page tours. In the old Android app, also the app's own update check
// and its notifications bell. Each page script calls bootShell() first and
// then does its own work.

import {
  COLOR_THEMES, applyColorTheme, applyMode, getStoredColorTheme, getStoredMode, getModePreference, initTheme,
} from "./theme.js";
import { hydrateIcons, openModal, closeModal } from "./ui.js";
import { initTray } from "./tray.js";
import { initUpdateBar } from "./sw-update.js";
import { initAppUpdate } from "./app-update.js";
import { initAppNotify } from "./app-notify.js";
import { initColourPickers } from "./colour-picker.js";
import { addTrayButton } from "./tray.js";
import { initBugReport, openBugReport } from "./bug-report.js";
import { initTours, openTourPicker } from "./tour.js";

// Report a bug's form and its Screenshot a page bar (js/bug-report.js), and Show me around's
// picker (js/tour.js): the same on every page, so made here rather than written into each.
const SHARED_MARKUP = `
  <div class="modal-backdrop hidden" id="bugModal">
    <div class="modal glass bug-modal" role="dialog" aria-modal="true" aria-labelledby="bugModalTitle">
      <div class="modal-head">
        <h2 id="bugModalTitle">Report a bug</h2>
        <button class="icon-btn small" type="button" data-close-modal="bugModal" aria-label="Close"><span data-icon="close"></span></button>
      </div>
      <form id="bugForm" novalidate>
        <label class="modal-section-label" for="bugText">What went wrong?</label>
        <textarea class="bug-text" id="bugText" maxlength="2000" rows="5" placeholder="What you did, what happened, and what you expected"></textarea>
        <label class="modal-section-label" for="bugContact">How to reach you <span class="bug-optional">(optional)</span></label>
        <input class="input" id="bugContact" type="text" maxlength="200" autocomplete="off" placeholder="Telegram @name or email, for an answer">
        <input class="bug-trap" id="bugWebsite" type="text" name="website" tabindex="-1" autocomplete="off" aria-hidden="true">
        <p class="modal-section-label">Pictures <span class="bug-optional">(optional)</span></p>
        <div class="bug-shots" id="bugShots" hidden></div>
        <div class="bug-shot-btns">
          <button class="btn" type="button" id="bugAddPic"><span data-icon="image"></span>Add pictures</button>
          <button class="btn" type="button" id="bugScreenshot"><span data-icon="screenshot"></span>Screenshot a page</button>
          <input type="file" id="bugPicFile" accept="image/*" multiple hidden>
        </div>
        <p class="mode-note">Up to 3. Screenshot a page puts this away: go to the page you want, or open a window, then press Screenshot this page. It takes the whole page, top to bottom, and brings you back here.</p>
        <p class="mode-note">Sent with it, to help find the bug: <span id="bugDetails"></span></p>
        <p class="bug-status" id="bugStatus" role="status" hidden></p>
        <div class="bug-foot"><button class="btn btn-primary" type="submit" id="bugSend"><span data-icon="send"></span>Send</button></div>
      </form>
    </div>
  </div>
  <div class="bug-shot-bar glass" id="bugShotBar" hidden>
    <button class="btn btn-primary" type="button" id="bugShotTake"><span data-icon="screenshot"></span><span id="bugShotTakeLabel">Screenshot this page</span></button>
    <button class="icon-btn" type="button" id="bugShotCancel" aria-label="Cancel" title="Cancel"><span data-icon="close"></span></button>
  </div>
  <div class="modal-backdrop hidden" id="tourModal">
    <div class="modal glass" role="dialog" aria-modal="true" aria-labelledby="tourModalTitle">
      <div class="modal-head">
        <h2 id="tourModalTitle">Show me around</h2>
        <button class="icon-btn small" type="button" data-close-modal="tourModal" aria-label="Close"><span data-icon="close"></span></button>
      </div>
      <div class="tour-picks" id="tourPicks"></div>
      <p class="mode-note">Each page shows you around the first time you open it. Pick one to see its tour again.</p>
    </div>
  </div>`;

// Adds the shared modals to the page, and the tray's Report a bug and Show me
// around buttons.
function addShared() {
  document.body.insertAdjacentHTML("beforeend", SHARED_MARKUP);
  const bugButton = addTrayButton({
    id: "bugBtn",
    icon: "bug",
    label: "Report a bug",
    onClick: () => {
      openBugReport();
    },
  });
  const tourButton = addTrayButton({
    id: "tourBtn",
    icon: "help",
    label: "Show me around",
    onClick: () => {
      openTourPicker();
    },
  });
  for (const button of [bugButton, tourButton]) {
    if (button) {
      button.setAttribute("aria-haspopup", "dialog");
    }
  }
}

// Fills the theme modal's swatches and wires its swatch and mode buttons.
function buildThemeModal() {
  const grid = document.getElementById("swatchGrid");
  grid.innerHTML = COLOR_THEMES.map((theme) => {
    return `
      <button class="swatch" data-theme-id="${theme.id}" style="--swatch-color:${theme.hex}" type="button" aria-label="${theme.label}">
        <span class="swatch-dot"></span>
        <span class="swatch-label">${theme.label}</span>
      </button>`;
  }).join("");

  syncThemeModalState();

  grid.addEventListener("click", (event) => {
    const swatchButton = event.target.closest("[data-theme-id]");
    if (!swatchButton) {
      return;
    }
    applyColorTheme(swatchButton.dataset.themeId);
    syncThemeModalState();
  });

  document.getElementById("modeToggle").addEventListener("click", (event) => {
    const modeButton = event.target.closest("[data-mode]");
    if (!modeButton) {
      return;
    }
    applyMode(modeButton.dataset.mode);
    syncThemeModalState();
  });

  // A tab left open across 09:00 or 18:00 re-resolves itself; redraw the
  // modal so the note and pressed state stay in step with the change.
  document.addEventListener("uwu:modechange", syncThemeModalState);
}

// Marks the active swatch and mode button, and updates the clock note and the
// theme button's icon.
function syncThemeModalState() {
  const activeTheme = getStoredColorTheme();
  const activePreference = getModePreference();
  const resolvedMode = getStoredMode();

  document.querySelectorAll("#swatchGrid .swatch").forEach((swatch) => {
    swatch.classList.toggle("active", swatch.dataset.themeId === activeTheme);
  });
  document.querySelectorAll("#modeToggle .mode-btn").forEach((modeButton) => {
    const isActive = modeButton.dataset.mode === activePreference;
    modeButton.classList.toggle("active", isActive);
    modeButton.setAttribute("aria-pressed", String(isActive));
  });

  const note = document.getElementById("modeNote");
  if (note) {
    note.hidden = activePreference !== "time";
    if (activePreference === "time") {
      note.textContent = `Following the clock. Currently ${resolvedMode}.`;
    }
  }

  updateThemeButtonIcon();
}

function updateThemeButtonIcon() {
  const iconSpan = document.querySelector("#themeBtn [data-icon]");
  if (!iconSpan) {
    return;
  }
  let iconName;
  if (getStoredMode() === "dark") {
    iconName = "moon";
  } else {
    iconName = "sun";
  }
  iconSpan.setAttribute("data-icon", iconName);
  hydrateIcons(document.getElementById("themeBtn"));
}

// Every way to close a modal (its close button, a tap on the backdrop, Escape
// for the topmost one), and the theme button opening the theme modal.
function wireModals() {
  document.querySelectorAll("[data-close-modal]").forEach((closeButton) => {
    closeButton.addEventListener("click", () => {
      closeModal(closeButton.dataset.closeModal);
    });
  });
  document.querySelectorAll(".modal-backdrop").forEach((backdrop) => {
    backdrop.addEventListener("click", (event) => {
      if (event.target === backdrop) {
        closeModal(backdrop.id);
      }
    });
  });
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") {
      return;
    }
    const topmostOpenModal = [...document.querySelectorAll(".modal-backdrop:not(.hidden)")].pop();
    if (topmostOpenModal) {
      closeModal(topmostOpenModal.id);
    }
  });
  document.getElementById("themeBtn").addEventListener("click", () => {
    openModal("themeModal");
  });
}

export function bootShell() {
  addShared();
  initTheme();
  // Before the page's own script reads a picker's value.
  initColourPickers();
  hydrateIcons();
  updateThemeButtonIcon();
  buildThemeModal();
  wireModals();
  initTray();
  initUpdateBar();
  // Both do nothing outside the app. The bell goes in first, so it sits above
  // the update button.
  initAppNotify();
  initAppUpdate();
  initBugReport();
  initTours();
}
