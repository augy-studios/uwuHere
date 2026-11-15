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
const SHARED = `
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

function addShared() {
  document.body.insertAdjacentHTML("beforeend", SHARED);
  const bug = addTrayButton({ id: "bugBtn", icon: "bug", label: "Report a bug", onClick: () => openBugReport() });
  const tour = addTrayButton({ id: "tourBtn", icon: "help", label: "Show me around", onClick: () => openTourPicker() });
  for (const b of [bug, tour]) if (b) b.setAttribute("aria-haspopup", "dialog");
}

function buildThemeModal() {
  const grid = document.getElementById("swatchGrid");
  grid.innerHTML = COLOR_THEMES.map(
    (t) => `
      <button class="swatch" data-theme-id="${t.id}" style="--swatch-color:${t.hex}" type="button" aria-label="${t.label}">
        <span class="swatch-dot"></span>
        <span class="swatch-label">${t.label}</span>
      </button>`
  ).join("");

  syncThemeModalState();

  grid.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-theme-id]");
    if (!btn) return;
    applyColorTheme(btn.dataset.themeId);
    syncThemeModalState();
  });

  document.getElementById("modeToggle").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-mode]");
    if (!btn) return;
    applyMode(btn.dataset.mode);
    syncThemeModalState();
  });

  // A tab left open across 09:00 or 18:00 re-resolves itself; redraw the
  // modal so the note and pressed state stay in step with the change.
  document.addEventListener("uwu:modechange", syncThemeModalState);
}

function syncThemeModalState() {
  const activeTheme = getStoredColorTheme();
  const activePreference = getModePreference();
  const resolvedMode = getStoredMode();

  document.querySelectorAll("#swatchGrid .swatch").forEach((el) => {
    el.classList.toggle("active", el.dataset.themeId === activeTheme);
  });
  document.querySelectorAll("#modeToggle .mode-btn").forEach((el) => {
    const isActive = el.dataset.mode === activePreference;
    el.classList.toggle("active", isActive);
    el.setAttribute("aria-pressed", String(isActive));
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
  const span = document.querySelector("#themeBtn [data-icon]");
  if (!span) return;
  span.setAttribute("data-icon", getStoredMode() === "dark" ? "moon" : "sun");
  hydrateIcons(document.getElementById("themeBtn"));
}

function wireModals() {
  document.querySelectorAll("[data-close-modal]").forEach((btn) => {
    btn.addEventListener("click", () => closeModal(btn.dataset.closeModal));
  });
  document.querySelectorAll(".modal-backdrop").forEach((backdrop) => {
    backdrop.addEventListener("click", (e) => {
      if (e.target === backdrop) closeModal(backdrop.id);
    });
  });
  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    const open = [...document.querySelectorAll(".modal-backdrop:not(.hidden)")].pop();
    if (open) closeModal(open.id);
  });
  document.getElementById("themeBtn").addEventListener("click", () => openModal("themeModal"));
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
