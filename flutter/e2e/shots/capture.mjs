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

const BASE_URL = "http://127.0.0.1:47481";
// The raw/ folder beside this file, as a path (with Windows' leading slash before a drive letter
// taken off).
const OUTPUT_FOLDER = new URL("./raw/", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
mkdirSync(OUTPUT_FOLDER, { recursive: true });

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

/**
 * The seeded events: a science lab with everyone in `people` checked in (one of them left early),
 * a book club and an ended Saturday run, all at fixed times so each picture comes out the same.
 */
function events() {
  const database = { events: {} };
  const minutesFromStart = (minutes) => {
    return new Date(Date.UTC(2026, 10, 16, 1, 30 + minutes)).toISOString();
  };
  const lab = makeEvent(database, {
    code: "K7QX2B",
    title: "Year 9 Science, Lab 2",
    buttonLabel: "I'm here!",
    buttonColor: "#9be7c4",
    noteLabel: "Student ID",
    allowP2p: true,
    allowLocation: true,
    allowTap: true,
    createdAt: minutesFromStart(-5),
  });
  people.forEach(([name, note, method, distance], personIndex) => {
    let leftEarlyAt = null;
    if (personIndex === 5) {
      leftEarlyAt = minutesFromStart(40);
    }
    lab.attendees.push({ id: `a${personIndex}`, name, note, method, distance, checkedInAt: minutesFromStart(personIndex * 2), leftEarlyAt });
  });
  const club = makeEvent(database, { code: "BCD234", title: "Book club", buttonLabel: "Here", buttonColor: "#ffcc99", createdAt: minutesFromStart(-2000) });
  const run = makeEvent(database, { code: "MNP567", title: "Saturday run", ended: true, endedAt: minutesFromStart(-3000), createdAt: minutesFromStart(-3200) });
  return { database, lab, club, run };
}

const notes = (version) => {
  return readFileSync(new URL(`../../../announcements/release-notes-${version}.md`, import.meta.url), "utf8");
};
const releasePage = (version) => {
  return `https://github.com/augy-studios/uwuHere/releases/tag/android-v${version}`;
};
const release = {
  version: "2.0.0",
  size: 41000000,
  sha256: null,
  apk: "https://github.com/augy-studios/uwuHere/releases/download/android-v2.0.0/uwuhere-2.0.0.apk",
  page: releasePage("2.0.0"),
  date: "2026-11-16T10:00:00Z",
  history: [
    { version: "2.0.0", date: "2026-11-16T10:00:00Z", notes: notes("2.0.0"), page: releasePage("2.0.0") },
    { version: "1.0.3", date: "2026-10-19T16:21:23Z", notes: notes("1.0.3"), page: releasePage("1.0.3") },
    { version: "1.0.2", date: "2026-10-17T17:57:51Z", notes: notes("1.0.2"), page: releasePage("1.0.2") },
    { version: "1.0.1", date: "2026-10-17T09:11:51Z", notes: notes("1.0.1"), page: releasePage("1.0.1") },
    { version: "1.0.0", date: "2026-10-16T21:28:32Z", notes: notes("1.0.0"), page: releasePage("1.0.0") },
  ],
};

// ---- driving the app ----

/**
 * Opens the app in a fresh browser context of the given size, with the API answered from the
 * seeded events, the store filled (`seed`, plus this device hosting the three events), and waits
 * till `ready` (by default the home page's heading) shows.
 */
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
  const { database, lab, club, run } = events();
  database.release = release;
  await mockApi(tab, database);
  await tab.addInitScript(
    ([extraValues, myEvents, showTours]) => {
      if (sessionStorage.getItem("seeded")) {
        return;
      }
      sessionStorage.setItem("seeded", "1");
      // As store.dart keeps them in a browser (tests/helpers.js).
      const put = (key, value) => {
        let encoded;
        if (typeof value === "string") {
          encoded = value;
        } else {
          encoded = JSON.stringify(value);
        }
        localStorage.setItem(`flutter.ls.${key}`, JSON.stringify(encoded));
      };
      put("uwuhere.hosted", myEvents);
      put("uwuhere.trayOpen", "1");
      put("uwuhere.profile", { name: "Priya Nair", note: "A0198" });
      if (!showTours) {
        put("uwuhere.tour.welcome", "done");
        put("uwuhere.tour.pages", ["host", "join"]);
      }
      for (const [key, value] of Object.entries(extraValues)) {
        put(key, value);
      }
    },
    [seed, hosted(lab, club, run), tours],
  );
  await passThroughEmptyLayers(tab);
  await tab.goto(`${BASE_URL}/${query}`);
  let readyLocator;
  if (ready) {
    readyLocator = ready(tab);
  } else {
    readyLocator = tab.getByRole("heading", { name: "Host an event" }).first();
  }
  await readyLocator.waitFor({ timeout: 30000 });
  await tab.waitForTimeout(800);
  return { context, page: tab, database, lab };
}

const button = (page, name, exact = true) => {
  return page.getByRole("button", { name, exact });
};
const hostPage = (query) => {
  return `${query}&page=host&id=K7QX2B`;
};
const hostReady = (page) => {
  return page.getByRole("heading", { name: "Year 9 Science, Lab 2" }).first();
};
const joinReady = (page) => {
  return page.getByRole("heading", { name: "Year 9 Science, Lab 2" }).first();
};

// Waits a moment (with the pointer out of the way), then saves the page as raw/<file>.png.
async function shot(page, file, { wait = 900 } = {}) {
  // The pointer off anything with a tooltip: the window's bottom left corner.
  await page.mouse.move(1, page.viewportSize().height - 1);
  await page.waitForTimeout(wait);
  await page.screenshot({ path: `${OUTPUT_FOLDER}${file}.png` });
  console.log(file);
}

// Ignores a wait that timed out: the picture is taken either way.
const ignoreTimeout = () => {};

// The eight screens, in the order the store shows them.
async function screens(browser, set, viewport, scale) {
  const androidQuery = (extra = "") => {
    return `?android=1${extra}`;
  };
  const uwuAppsLook = { "app.look": "uwuapps" };

  let { context, page } = await open(browser, { viewport, scale, query: androidQuery(), seed: uwuAppsLook });
  await shot(page, `${set}-01-home`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: hostPage(androidQuery()), seed: uwuAppsLook, ready: hostReady }));
  // Same wifi ready (through PeerJS's broker).
  await page.getByText(/^Ready for same-wifi check-ins/).first().waitFor({ timeout: 20000 }).catch(ignoreTimeout);
  await shot(page, `${set}-02-host`);
  // Further down: the list.
  await page.mouse.move(viewport.width / 2, viewport.height * 0.6);
  for (let scrollStep = 0; scrollStep < 9; scrollStep = scrollStep + 1) {
    await page.mouse.wheel(0, 300);
    await page.waitForTimeout(100);
  }
  await shot(page, `${set}-03-list`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: `${androidQuery()}&page=join&id=K7QX2B`, seed: uwuAppsLook, ready: joinReady }));
  await shot(page, `${set}-04-checkin`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: hostPage(androidQuery("&wallpaper=1")), seed: { "app.look": "material" }, ready: hostReady }));
  await button(page, "Show the QR code big").click();
  await page.getByRole("heading", { name: "Scan to check in" }).waitFor();
  await shot(page, `${set}-05-qr`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: androidQuery(), seed: { ...uwuAppsLook, "uwuhere.colorTheme": "not-green-4" } }));
  await button(page, "Theme").click();
  await page.getByRole("heading", { name: "Theme" }).waitFor();
  await shot(page, `${set}-06-theme`);
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: androidQuery("&wallpaper=1"), seed: { "app.look": "material" } }));
  await button(page, "Check for updates").click();
  await page.getByText("Every version").waitFor();
  // "You have the newest version" gone first.
  await shot(page, `${set}-07-updates`, { wait: 4000 });
  await context.close();

  ({ context, page } = await open(browser, {
    viewport,
    scale,
    query: hostPage(androidQuery()),
    seed: { ...uwuAppsLook, "uwuhere.mode": "dark", "uwuhere.tour.welcome": "done" },
    tours: true,
    ready: hostReady,
  }));
  await button(page, "Skip").waitFor({ timeout: 10000 });
  await button(page, "Next").click();
  await page.waitForTimeout(800);
  await shot(page, `${set}-08-dark-tour`);
  await context.close();
}

// The eight desktop screens: the desktop app's window at 1440 × 900, and Make it yours.
async function desktop(browser) {
  const viewport = { width: 1440, height: 900 };
  const scale = 2;
  const desktopQuery = "?desktop=1";
  const uwuAppsLook = { "app.look": "uwuapps" };
  let { context, page } = await open(browser, { viewport, scale, query: desktopQuery, seed: uwuAppsLook });
  await shot(page, "desktop-01-home");

  await page.getByRole("button", { name: /^Year 9 Science/ }).click();
  await hostReady(page).waitFor();
  await page.getByText(/^Ready for same-wifi check-ins/).first().waitFor({ timeout: 20000 }).catch(ignoreTimeout);
  await shot(page, "desktop-02-host");

  // The command bar, in the middle of the title bar.
  await page.keyboard.press("Control+k");
  await page.waitForTimeout(400);
  await page.getByRole("textbox", { name: /^Search/ }).click();
  await page.waitForTimeout(400);
  await page.keyboard.type("b", { delay: 40 });
  await page.waitForTimeout(500);
  await shot(page, "desktop-03-command");
  await page.keyboard.press("Escape");
  await page.waitForTimeout(300);

  await button(page, "Show the QR code").click();
  await page.getByRole("heading", { name: "Scan to check in" }).waitFor();
  await shot(page, "desktop-04-qr");
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: `${desktopQuery}&page=join&id=K7QX2B`, seed: uwuAppsLook, ready: joinReady }));
  await shot(page, "desktop-05-checkin");
  await context.close();

  ({ context, page } = await open(browser, {
    viewport: { width: 940, height: 660 },
    scale,
    query: "?welcome=1",
    seed: { "uwuhere.colorTheme": "classic" },
    ready: (welcomePage) => {
      return welcomePage.getByText("Get started");
    },
  }));
  await shot(page, "desktop-06-welcome");
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: hostPage(desktopQuery), seed: { ...uwuAppsLook, "uwuhere.mode": "dark", "uwuhere.colorTheme": "not-green-2" }, ready: hostReady }));
  await shot(page, "desktop-07-dark");
  await context.close();

  ({ context, page } = await open(browser, { viewport, scale, query: hostPage(desktopQuery), seed: uwuAppsLook, ready: hostReady }));
  await button(page, "Event settings").click();
  await page.getByRole("heading", { name: "Event settings" }).waitFor();
  await shot(page, "desktop-08-settings");
  await context.close();
}

const browser = await chromium.launch();
const onlySet = process.argv[2];
try {
  if (!onlySet || onlySet === "phone") {
    await screens(browser, "phone", { width: 412, height: 892 }, 3);
  }
  if (!onlySet || onlySet === "tablet7") {
    await screens(browser, "tablet7", { width: 600, height: 1000 }, 2.7);
  }
  if (!onlySet || onlySet === "tablet10") {
    await screens(browser, "tablet10", { width: 1280, height: 800 }, 2);
  }
  if (!onlySet || onlySet === "desktop") {
    await desktop(browser);
  }
} finally {
  await browser.close();
}
