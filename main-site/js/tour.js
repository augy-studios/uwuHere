// First-visit tours (docs/page-tour-spec.md): the page dims, one thing on it is lit, and a chalk
// arrow runs to it from a line saying what it does. Next moves on, Skip ends it. A tour for each
// page (home, which is also the welcome, the host page and the check-in page), each shown the
// first time it's on screen; the Edge Tray's Show me around replays them. The same tours, under
// the same keys, as the apps' (flutter/lib/features/tour/).
//
// Each step's element is scrolled into view before it's lit, wherever on the page it is, and the
// card and its arrow stay on screen, following the element as the page scrolls or the window
// changes size (§3): below or above the element if there's room, else beside it, else on a solid
// backing at the far end, without an arrow.
//
// The pages are separate documents. Home's tour, asked for on another page, goes there with
// ?tour=home, runs, and comes back.

const WELCOME_KEY = "uwuhere.tour.welcome";
const PAGES_KEY = "uwuhere.tour.pages";
const PAD = 8;
const START = "home";

const TOURS = {
  home: {
    label: "Home",
    steps: [
      { el: "#joinForm", text: "Checking in? Type the code from the host's screen, or scan their QR code with your camera." },
      { el: "#hostedCard", text: "Events you host on this device. Hosting from another one? Open it here with its code and password." },
      { el: "#createForm", text: "Host an event: give it a name, pick the button, and how people prove they are here." },
      { el: "#methods", text: "Same wifi, location, tapping phones or Bluetooth. Pick one or more." },
      { el: "#tourBtn, #trayTab", text: "Show me around plays these tours again. Report a bug and the theme are here too." },
    ],
  },
  host: {
    label: "Host page",
    steps: [
      { el: "#codeBtn", text: "The event code. Tap it to copy the link to check in." },
      { el: "#qrHolder", text: "People scan this with their phone's camera to check in." },
      { el: "#qrShowBtn", text: "Turn your screen to the room: the code as big as it goes." },
      { el: "#p2pRow, #locRow, #tapRow, #btRow", text: "How check-ins are arriving. Keep this page open for same-wifi check-ins." },
      { el: "#addForm, #listTitle", text: "Everyone who is here, live. Add someone by hand, or remove someone." },
      { el: "#liveActions", text: "Pause check-ins, download the list as a CSV, or end the event." },
      { el: "#settingsBtn, #trayTab", text: "Event settings: the name, the button, the ways in, and a password." },
    ],
  },
  join: {
    label: "Check-in page",
    steps: [
      { el: "#whoCard", text: "Your name, as the host will see it. It is remembered for next time." },
      { el: "#hereBtn", text: "Press it to check in. It checks you are near the host first." },
      { el: "#leaveBtn", text: "Leaving before the end? Tell the host here, once you are checked in." },
    ],
  },
};

/* ---- the pages ---- */

const path = () => location.pathname.replace(/\.html$/, "");

const pages = {
  active() {
    // A window over the page: no tour starts under it by itself.
    if (document.querySelector(".modal-backdrop:not(.hidden)")) return null;
    if (path().startsWith("/host")) return document.getElementById("hostView")?.hidden === false ? "host" : null;
    if (path().startsWith("/join")) return document.getElementById("checkinView")?.hidden === false ? "join" : null;
    return "home";
  },
  open(id) {
    if (id === "home" && path() !== "/" && path() !== "/index") {
      cameBack = location.pathname + location.search;
      sessionStorage.setItem("uwuhere.tourBack", cameBack);
      location.href = "/?tour=home";
    }
  },
};

/* ---- seen ---- */

function seen(id) {
  try {
    if (id === START) return localStorage.getItem(WELCOME_KEY) === "done";
    return JSON.parse(localStorage.getItem(PAGES_KEY) || "[]").includes(id);
  } catch {
    // Broken storage counts every tour as seen, rather than showing one on every visit.
    return true;
  }
}

function markSeen(id) {
  try {
    if (id === START) return localStorage.setItem(WELCOME_KEY, "done");
    const list = JSON.parse(localStorage.getItem(PAGES_KEY) || "[]");
    if (!list.includes(id)) localStorage.setItem(PAGES_KEY, JSON.stringify([...list, id]));
  } catch {
    // Shown again next time.
  }
}

/* ---- the layer ---- */

let steps = [];
let at = 0;
let root = null;
let page = null;
let cameBack = null;

/* Shown: not hidden, not behind inert, and not off the side in a put away tray. Above or below
   what's on screen is fine: it's scrolled to. */
function visible(el) {
  if (!el || el.closest("[hidden]") || el.closest("[inert]") || el.closest(".hidden")) return false;
  const r = el.getBoundingClientRect();
  if (r.width <= 0 || r.height <= 0) return false;
  if (r.right <= 0 || r.left >= innerWidth) return false;
  return getComputedStyle(el).visibility !== "hidden";
}
const target = (s) => [...document.querySelectorAll(s.el)].find(visible) || null;

function build() {
  root = document.createElement("div");
  root.className = "tour";
  root.setAttribute("role", "dialog");
  root.setAttribute("aria-modal", "true");
  root.setAttribute("aria-labelledby", "tourText");
  root.innerHTML =
    '<div class="tourHole"></div>' +
    '<svg class="tourArrow" aria-hidden="true"><defs><filter id="tourChalk"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="2.5"/></filter></defs>' +
    '<path class="tourLine" filter="url(#tourChalk)"/><path class="tourHead" filter="url(#tourChalk)"/></svg>' +
    '<button class="tourSkip" type="button">Skip</button>' +
    '<div class="tourCard"><p id="tourText" class="tourText" aria-live="polite"></p>' +
    '<div class="tourFoot"><span class="tourDots" aria-hidden="true"></span><button class="tourNext" type="button">Next</button></div></div>';
  document.body.appendChild(root);
  root.querySelector(".tourSkip").addEventListener("click", end);
  root.querySelector(".tourNext").addEventListener("click", next);
  root.addEventListener("keydown", (e) => {
    e.stopPropagation();
    if (e.key === "Escape") end();
    if (e.key === "ArrowRight") next();
  });
  window.addEventListener("resize", place);
  window.addEventListener("scroll", place, true);
}

function show(i) {
  at = i;
  const el = steps[i].target;
  // §3.1: a tall element from its top.
  const tall = el.getBoundingClientRect().height > innerHeight * 0.6;
  el.scrollIntoView({ block: tall ? "start" : "center", behavior: "instant" });
  root.querySelector(".tourText").textContent = steps[i].text;
  // Placed again for a moment after: the page can still be settling (a font, a tray sliding).
  const until = performance.now() + 600;
  const follow = () => {
    place();
    if (root && performance.now() < until) requestAnimationFrame(follow);
  };
  root.querySelector(".tourDots").innerHTML = steps.map((_, n) => `<span${n === i ? ' class="on"' : ""}></span>`).join("");
  root.querySelector(".tourNext").textContent = i === steps.length - 1 ? "Done" : "Next";
  requestAnimationFrame(follow);
  root.querySelector(".tourNext").focus({ preventScroll: true });
}

const M = 12;
const EDGE = 20;
const GAP_MIN = 36;
const GAP_MAX = 70;
const CARD_MIN = 220;
const clamp = (lo, v, hi) => Math.max(lo, Math.min(v, Math.max(lo, hi)));

/* §3: the hole, the card on the side with room, lined up with the element, and the arrow
   between them, all of it on screen. */
function place() {
  if (!root) return;
  const el = steps[at]?.target;
  if (!el) return;
  const r = el.getBoundingClientRect();
  const vw = innerWidth;
  const vh = innerHeight;
  Object.assign(root.querySelector(".tourHole").style, {
    left: `${r.left - PAD}px`,
    top: `${r.top - PAD}px`,
    width: `${r.width + PAD * 2}px`,
    height: `${r.height + PAD * 2}px`,
  });
  const v = { left: Math.max(r.left, 0), right: Math.min(r.right, vw), top: Math.max(r.top, 0), bottom: Math.min(r.bottom, vh) };
  const card = root.querySelector(".tourCard");
  card.classList.remove("solid");
  card.style.width = "";
  let cw = card.offsetWidth;
  let ch = card.offsetHeight;
  const room = { below: vh - v.bottom - PAD - M, above: v.top - PAD - M, right: vw - v.right - PAD - M, left: v.left - PAD - M };
  let side = null;
  if (Math.max(room.below, room.above) >= ch + GAP_MIN) side = room.below >= room.above ? "below" : "above";
  else {
    const s = room.right >= room.left ? "right" : "left";
    const fit = room[s] - GAP_MIN;
    if (fit >= Math.min(cw, CARD_MIN)) {
      if (fit < cw) {
        card.style.width = `${fit}px`;
        cw = card.offsetWidth;
        ch = card.offsetHeight;
      }
      if (ch <= vh - M * 2) side = s;
      else card.style.width = "";
    }
  }
  const line = root.querySelector(".tourLine");
  const head = root.querySelector(".tourHead");
  let left;
  let top;
  if (!side) {
    card.classList.add("solid");
    cw = card.offsetWidth;
    ch = card.offsetHeight;
    left = (vw - cw) / 2;
    top = (v.top + v.bottom) / 2 > vh / 2 ? M : vh - ch - M;
    Object.assign(card.style, { left: `${left}px`, top: `${top}px` });
    line.setAttribute("d", "");
    head.setAttribute("d", "");
    return;
  }
  const midX = (v.left + v.right) / 2;
  const midY = (v.top + v.bottom) / 2;
  let sx;
  let sy;
  let tx;
  let ty;
  if (side === "below" || side === "above") {
    const gap = clamp(GAP_MIN, room[side] - ch, GAP_MAX);
    left = clamp(M, midX - cw / 2, vw - cw - M);
    top = side === "below" ? v.bottom + PAD + gap : v.top - PAD - gap - ch;
    top = clamp(M, top, vh - ch - M);
    tx = clamp(v.left + 12, midX, v.right - 12);
    ty = side === "below" ? v.bottom + PAD + 4 : v.top - PAD - 4;
    sx = clamp(left + 24, tx, left + cw - 24);
    sy = side === "below" ? top - 6 : top + ch + 6;
  } else {
    const gap = clamp(GAP_MIN, room[side] - cw, GAP_MAX);
    left = side === "right" ? v.right + PAD + gap : v.left - PAD - gap - cw;
    left = clamp(M, left, vw - cw - M);
    top = clamp(M, midY - ch / 2, vh - ch - M);
    tx = side === "right" ? v.right + PAD + 4 : v.left - PAD - 4;
    ty = clamp(v.top + 12, midY, v.bottom - 12);
    sx = side === "right" ? left - 6 : left + cw + 6;
    sy = clamp(top + 16, ty, top + ch - 16);
  }
  Object.assign(card.style, { left: `${left}px`, top: `${top}px` });
  const inX = (x) => clamp(EDGE, x, vw - EDGE);
  const inY = (y) => clamp(EDGE, y, vh - EDGE);
  tx = inX(tx);
  ty = inY(ty);
  sx = inX(sx);
  sy = inY(sy);
  const dx = tx - sx;
  const dy = ty - sy;
  const mx = inX((sx + tx) / 2 - dy * 0.2);
  const my = inY((sy + ty) / 2 + dx * 0.2);
  root.querySelector(".tourArrow").setAttribute("viewBox", `0 0 ${vw} ${vh}`);
  line.setAttribute("d", `M${sx},${sy} Q${mx},${my} ${tx},${ty}`);
  line.style.setProperty("--len", Math.ceil(line.getTotalLength()) + 10);
  const ang = Math.atan2(ty - my, tx - mx);
  const a1 = ang + Math.PI * 0.8;
  const a2 = ang - Math.PI * 0.8;
  const len = 14;
  head.setAttribute("d", `M${tx + Math.cos(a1) * len},${ty + Math.sin(a1) * len} L${tx},${ty} L${tx + Math.cos(a2) * len},${ty + Math.sin(a2) * len}`);
}

function next() {
  if (at < steps.length - 1) show(at + 1);
  else end();
}

function end() {
  if (page) markSeen(page);
  removeEventListener("resize", place);
  removeEventListener("scroll", place, true);
  root?.remove();
  root = null;
  page = null;
  document.body.classList.remove("touring");
  // A replay that came over from another page goes back to it.
  if (cameBack) {
    const back = cameBack;
    cameBack = null;
    sessionStorage.removeItem("uwuhere.tourBack");
    location.href = back;
    return;
  }
  setTimeout(forPage, 600);
}

/** `id`'s tour, on its page. */
export function startTour(id) {
  if (root || !TOURS[id]) return;
  if (pages.active() !== id) {
    // Over on another document: it starts there.
    if (id === "home") pages.open(id);
    return;
  }
  setTimeout(() => {
    steps = TOURS[id].steps.map((s) => ({ ...s, target: target(s) })).filter((s) => s.target);
    if (!steps.length) {
      markSeen(id);
      return;
    }
    page = id;
    document.body.classList.add("touring");
    build();
    show(0);
  }, 400);
}

let waiting = null;

/* The tour for what's on screen, the first time, once it's drawn. */
function forPage() {
  const id = pages.active();
  if (!id || root || seen(id) || !TOURS[id]) return;
  clearInterval(waiting);
  let tries = 0;
  waiting = setInterval(() => {
    tries++;
    if (pages.active() !== id || root) return clearInterval(waiting);
    if (tries < 2) return;
    clearInterval(waiting);
    startTour(id);
  }, 500);
}

/** At start-up: a replay asked for by the link, or the page's first tour once it's drawn. */
export function initTours() {
  const params = new URLSearchParams(location.search);
  const asked = params.get("tour");
  if (asked && TOURS[asked]) {
    cameBack = sessionStorage.getItem("uwuhere.tourBack");
    history.replaceState(null, "", location.pathname);
    setTimeout(() => startTour(asked), 900);
    return;
  }
  // A host or check-in page draws its event a moment after it opens, and closing a window shows
  // the page again: either can be when its tour starts.
  new MutationObserver(() => setTimeout(forPage, 300)).observe(document.body, { attributes: true, subtree: true, attributeFilter: ["class", "hidden"] });
  setTimeout(forPage, 1000);
}

/** The Edge Tray's Show me around: this page's tour, and home's. */
export function openTourPicker() {
  const here = pages.active();
  const ids = [...new Set([here, "home"].filter((id) => id && TOURS[id]))];
  if (ids.length === 1) return startTour(ids[0]);
  const modal = document.getElementById("tourModal");
  if (!modal) return startTour(ids[0]);
  const box = modal.querySelector("#tourPicks");
  box.innerHTML = ids.map((id) => `<button class="btn" type="button" data-tour="${id}">${TOURS[id].label}</button>`).join("");
  box.onclick = (e) => {
    const btn = e.target.closest("[data-tour]");
    if (!btn) return;
    modal.classList.add("hidden");
    document.body.classList.remove("modal-open");
    setTimeout(() => startTour(btn.dataset.tour), 300);
  };
  modal.classList.remove("hidden");
  document.body.classList.add("modal-open");
}
