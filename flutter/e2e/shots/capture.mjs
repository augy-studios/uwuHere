// Takes the pictures the store screenshots are made from (compose.mjs frames them): the app's real
// screens, from the browser build (../README.md), with the same seeded events each time.
//
//     node shots/capture.mjs            with serve.mjs running; pictures land in shots/raw/
//     node shots/capture.mjs phone      one set only: phone, tablet7, tablet10 or desktop
//
// Four sets: phone (412 × 892 at 3×), 7-inch tablet (600 × 1000 at 2.7×), 10-inch tablet
// (1280 × 800 at 2×) and desktop (1440 × 900 at 2×, with the desktop's title bar).
import { chromium } from "@playwright/test";
import { mkdirSync, readFileSync } from "node:fs";
import { hosted, makeEvent, mockApi, passThroughEmptyLayers } from "../tests/helpers.js";

const BASE = "http://127.0.0.1:47481";
const OUT = new URL("./raw/", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
mkdirSync(OUT, { recursive: true });

// ---- the events ----

const people = [
  ["Alex Tan", "A0231", "p2p", null],
  ["Priya Nair", "A0198", "location", 18],
  ["Sam Lee", "A0244", "tap", null],
  ["Jo Lim", "A0207", "p2p", null],
  ["Noor Aziz", "A0219", "mesh", null],
  ["Kim Park", "A0236", "location", 41],
  ["Robin Ong", "A0252", "manual", null],
  ["Lou Chen", "A0213", "hotspot", null],
];

function events() {
  const db = { events: {} };
  const minutes = (m) => new Date(Date.UTC(2026, 10, 16, 1, 30 + m)).toISOString();
  const lab = makeEvent(db, {
    code: "K7QX2B",
    title: "Year 9 Science, Lab 2",
    buttonLabel: "I'm here!",
    buttonColor: "#9be7c4",
    noteLabel: "Student ID",
    allowP2p: true,
    allowLocation: true,
    allowTap: true,
    createdAt: minutes(-5),
  });
  people.forEach(([name, note, method, distance], i) => {
    lab.attendees.push({ id: `a${i}`, name, note, method, distance, checkedInAt: minutes(i * 2), leftEarlyAt: i === 5 ? minutes(40) : null });
  });
  const club = makeEvent(db, { code: "BCD234", title: "Book club", buttonLabel: "Here", buttonColor: "#ffcc99", createdAt: minutes(-2000) });
  const run = makeEvent(db, { code: "MNP567", title: "Saturday run", ended: true, endedAt: minutes(-3000), createdAt: minutes(-3200) });
  return { db, lab, club, run };
}

const notes = (v) => readFileSync(new URL(`../../../announcements/release-notes-${v}.md`, import.meta.url), "utf8");
const page = (v) => `https://github.com/augy-studios/uwuHere/releases/tag/android-v${v}`;
const release = {
  version: "2.0.0",
  size: 41000000,
  sha256: null,
  apk: "https://github.com/augy-studios/uwuHere/releases/download/android-v2.0.0/uwuhere-2.0.0.apk",
  page: page("2.0.0"),
  date: "2026-11-16T10:00:00Z",
  history: [
    { version: "2.0.0", date: "2026-11-16T10:00:00Z", notes: notes("2.0.0"), page: page("2.0.0") },
    { version: "1.0.3", date: "2026-10-19T16:21:23Z", notes: notes("1.0.3"), page: page("1.0.3") },
    { version: "1.0.2", date: "2026-10-17T17:57:51Z", notes: notes("1.0.2"), page: page("1.0.2") },
    { version: "1.0.1", date: "2026-10-17T09:11:51Z", notes: notes("1.0.1"), page: page("1.0.1") },
    { version: "1.0.0", date: "2026-10-16T21:28:32Z", notes: notes("1.0.0"), page: page("1.0.0") },
  ],
};

// ---- driving the app ----

async function open(browser, { viewport, scale, query = "", seed = {}, tours = false, ready }) {
  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: scale,
    hasTouch: viewport.width < 1000,
    isMobile: viewport.width < 1000,
    geolocation: { latitude: 1.3521, longitude: 103.8198 },
    permissions: ["geolocation"],
  });
  const tab = await context.newPage();
  const { db, lab, club, run } = events();
  db.release = release;
  await mockApi(tab, db);
  await tab.addInitScript(
    ([extra, mine, tours]) => {
      if (sessionStorage.getItem("seeded")) return;
      sessionStorage.setItem("seeded", "1");
      // As store.dart keeps them in a browser (tests/helpers.js).
      const put = (k, v) => localStorage.setItem(`flutter.ls.${k}`, JSON.stringify(typeof v === "string" ? v : JSON.stringify(v)));
      put("uwuhere.hosted", mine);
      put("uwuhere.trayOpen", "1");
      put("uwuhere.profile", { name: "Priya Nair", note: "A0198" });
      if (!tours) {
        put("uwuhere.tour.welcome", "done");
        put("uwuhere.tour.pages", ["host", "join"]);
      }
      for (const [k, v] of Object.entries(extra)) put(k, v);
    },
    [seed, hosted(lab, club, run), tours],
  );
  await passThroughEmptyLayers(tab);
  await tab.goto(`${BASE}/${query}`);
  await (ready ? ready(tab) : tab.getByRole("heading", { name: "Host an event" }).first()).waitFor({ timeout: 30000 });
  await tab.waitForTimeout(800);
  return { context, page: tab, db, lab };
}

const btn = (p, name, exact = true) => p.getByRole("button", { name, exact });
const hostPage = (q) => `${q}&page=host&id=K7QX2B`;
const hostReady = (p) => p.getByRole("heading", { name: "Year 9 Science, Lab 2" }).first();
const joinReady = (p) => p.getByRole("heading", { name: "Year 9 Science, Lab 2" }).first();

async function shot(p, file, { wait = 900 } = {}) {
  // The pointer off anything with a tooltip: the window's bottom left corner.
  await p.mouse.move(1, p.viewportSize().height - 1);
  await p.waitForTimeout(wait);
  await p.screenshot({ path: `${OUT}${file}.png` });
  console.log(file);
}

// The eight screens, in the order the store shows them.
async function screens(browser, set, viewport, scale) {
  const q = (s = "") => `?android=1${s}`;
  const uwu = { "app.look": "uwuapps" };

  let { context, page: p } = await open(browser, { viewport, scale, query: q(), seed: uwu });
  await shot(p, `${set}-01-home`);
  await context.close();

  ({ context, page: p } = await open(browser, { viewport, scale, query: hostPage(q()), seed: uwu, ready: hostReady }));
  // Same wifi ready (through PeerJS's broker).
  await p.getByText(/^Ready for same-wifi check-ins/).first().waitFor({ timeout: 20000 }).catch(() => {});
  await shot(p, `${set}-02-host`);
  // Further down: the list.
  await p.mouse.move(viewport.width / 2, viewport.height * 0.6);
  for (let i = 0; i < 9; i++) {
    await p.mouse.wheel(0, 300);
    await p.waitForTimeout(100);
  }
  await shot(p, `${set}-03-list`);
  await context.close();

  ({ context, page: p } = await open(browser, { viewport, scale, query: `${q()}&page=join&id=K7QX2B`, seed: uwu, ready: joinReady }));
  await shot(p, `${set}-04-checkin`);
  await context.close();

  ({ context, page: p } = await open(browser, { viewport, scale, query: hostPage(q("&wallpaper=1")), seed: { "app.look": "material" }, ready: hostReady }));
  await btn(p, "Show the QR code big").click();
  await p.getByRole("heading", { name: "Scan to check in" }).waitFor();
  await shot(p, `${set}-05-qr`);
  await context.close();

  ({ context, page: p } = await open(browser, { viewport, scale, query: q(), seed: { ...uwu, "uwuhere.colorTheme": "not-green-4" } }));
  await btn(p, "Theme").click();
  await p.getByRole("heading", { name: "Theme" }).waitFor();
  await shot(p, `${set}-06-theme`);
  await context.close();

  ({ context, page: p } = await open(browser, { viewport, scale, query: q("&wallpaper=1"), seed: { "app.look": "material" } }));
  await btn(p, "Check for updates").click();
  await p.getByText("Every version").waitFor();
  // "You have the newest version" gone first.
  await shot(p, `${set}-07-updates`, { wait: 4000 });
  await context.close();

  ({ context, page: p } = await open(browser, {
    viewport,
    scale,
    query: hostPage(q()),
    seed: { ...uwu, "uwuhere.mode": "dark", "uwuhere.tour.welcome": "done" },
    tours: true,
    ready: hostReady,
  }));
  await btn(p, "Skip").waitFor({ timeout: 10000 });
  await btn(p, "Next").click();
  await p.waitForTimeout(800);
  await shot(p, `${set}-08-dark-tour`);
  await context.close();
}

async function desktop(browser) {
  const viewport = { width: 1440, height: 900 };
  const scale = 2;
  const q = "?desktop=1";
  const uwu = { "app.look": "uwuapps" };
  let { context, page: p } = await open(browser, { viewport, scale, query: q, seed: uwu });
  await shot(p, "desktop-01-home");

  await p.getByRole("button", { name: /^Year 9 Science/ }).click();
  await hostReady(p).waitFor();
  await p.getByText(/^Ready for same-wifi check-ins/).first().waitFor({ timeout: 20000 }).catch(() => {});
  await shot(p, "desktop-02-host");

  // The command bar, in the middle of the title bar.
  await p.keyboard.press("Control+k");
  await p.waitForTimeout(400);
  await p.getByRole("textbox", { name: /^Search/ }).click();
  await p.waitForTimeout(400);
  await p.keyboard.type("b", { delay: 40 });
  await p.waitForTimeout(500);
  await shot(p, "desktop-03-command");
  await p.keyboard.press("Escape");
  await p.waitForTimeout(300);

  await btn(p, "Show the QR code").click();
  await p.getByRole("heading", { name: "Scan to check in" }).waitFor();
  await shot(p, "desktop-04-qr");
  await context.close();

  ({ context, page: p } = await open(browser, { viewport, scale, query: `${q}&page=join&id=K7QX2B`, seed: uwu, ready: joinReady }));
  await shot(p, "desktop-05-checkin");
  await context.close();

  ({ context, page: p } = await open(browser, {
    viewport: { width: 940, height: 660 },
    scale,
    query: "?welcome=1",
    seed: { "uwuhere.colorTheme": "classic" },
    ready: (x) => x.getByText("Get started"),
  }));
  await shot(p, "desktop-06-welcome");
  await context.close();

  ({ context, page: p } = await open(browser, { viewport, scale, query: hostPage(q), seed: { ...uwu, "uwuhere.mode": "dark", "uwuhere.colorTheme": "not-green-2" }, ready: hostReady }));
  await shot(p, "desktop-07-dark");
  await context.close();

  ({ context, page: p } = await open(browser, { viewport, scale, query: hostPage(q), seed: uwu, ready: hostReady }));
  await btn(p, "Event settings").click();
  await p.getByRole("heading", { name: "Event settings" }).waitFor();
  await shot(p, "desktop-08-settings");
  await context.close();
}

const browser = await chromium.launch();
const only = process.argv[2];
try {
  if (!only || only === "phone") await screens(browser, "phone", { width: 412, height: 892 }, 3);
  if (!only || only === "tablet7") await screens(browser, "tablet7", { width: 600, height: 1000 }, 2.7);
  if (!only || only === "tablet10") await screens(browser, "tablet10", { width: 1280, height: 800 }, 2);
  if (!only || only === "desktop") await desktop(browser);
} finally {
  await browser.close();
}
