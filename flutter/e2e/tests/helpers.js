import { expect } from "@playwright/test";

export const API = "https://here.uwuapps.org/api";

let counter = 0;
const CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXYZ23456789";
const newCode = () => Array.from({ length: 6 }, (_, i) => CODE_ALPHABET[(counter * 7 + i * 11 + 3) % CODE_ALPHABET.length]).join("");
const hostKeyFor = (code) => `${code}`.padEnd(43, "k").slice(0, 43);

/** An event as the server keeps it, in db.events[code]. */
export function makeEvent(db, fields = {}) {
  counter += 1;
  const code = fields.code ?? newCode();
  const now = new Date().toISOString();
  const event = {
    code,
    title: "",
    buttonLabel: "I'm here",
    buttonColor: "#ccffcc",
    noteLabel: null,
    allowP2p: false,
    allowLocation: true,
    allowTap: false,
    allowBluetooth: false,
    hasLocation: true,
    radius: 100,
    paused: false,
    createdAt: now,
    ended: false,
    endedAt: null,
    hasPassword: false,
    ...fields,
  };
  db.events[code] = { event, attendees: [], hostKey: hostKeyFor(code), password: fields.password ?? null, devices: {} };
  return db.events[code];
}

/**
 * uwuHere's API (main-site/api/*), answered here from an in-memory store, so the suite runs
 * offline and the same every time: events, the host's actions, check-ins by location and by tap,
 * leaving early, unlocking with a password, the release check and Report a bug. Every request is
 * kept in `db.requests`.
 */
export async function mockApi(page, db = {}) {
  db.requests = [];
  db.events ??= {};
  db.release ??= { version: null, history: [] };
  await page.route(`${API}/**`, async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const path = url.pathname.replace(/^\/api/, "");
    const body = req.postData() ? JSON.parse(req.postData()) : null;
    db.requests.push({ method: req.method(), path, body, query: Object.fromEntries(url.searchParams) });
    const headers = { "access-control-allow-origin": "*", "access-control-allow-headers": "*" };
    const raw = (status, data) => route.fulfill({ status, contentType: "application/json", headers, body: JSON.stringify(data) });
    const ok = (data) => raw(200, { ok: true, data });
    const fail = (status, reason, error) => raw(status, { ok: false, reason, error });
    if (req.method() === "OPTIONS") {
      return route.fulfill({ status: 204, headers: { ...headers, "access-control-allow-methods": "*" } });
    }
    if (db.offline) return route.abort("internetdisconnected");
    const snapshot = (e) => ({ event: e.event, attendees: e.attendees });
    switch (path) {
      case "/app-release":
        return raw(200, db.release);
      case "/bug-report":
        (db.bugReports ??= []).push(body);
        if (db.bugStatus && db.bugStatus !== 200) return raw(db.bugStatus, { error: "Bug reports can't be sent from the app yet." });
        return raw(200, { id: "20261116-7K3Q" });
      case "/events": {
        const e = makeEvent(db, {
          title: body.title ?? "",
          buttonLabel: body.buttonLabel,
          buttonColor: body.buttonColor,
          noteLabel: body.noteLabel || null,
          allowP2p: body.allowP2p,
          allowLocation: body.allowLocation,
          allowTap: body.allowTap,
          allowBluetooth: body.allowBluetooth,
          radius: body.radius,
          hasLocation: Boolean(body.location),
          hasPassword: Boolean(body.password),
          password: body.password ?? null,
        });
        return ok({ code: e.event.code, hostKey: e.hostKey, ...snapshot(e) });
      }
      case "/event": {
        const e = db.events[url.searchParams.get("code")];
        if (!e) return fail(404, "not-found", "No event with that code.");
        const { hasPassword, ...pub } = e.event;
        const device = req.headers()["x-uwuhere-device"];
        const me = device && e.devices[device];
        return ok({ ...pub, me: me ? { checkedInAt: me.checkedInAt, leftEarlyAt: me.leftEarlyAt } : null });
      }
      case "/checkin": {
        const e = db.events[body.code];
        if (!e) return fail(404, "not-found", "No event with that code.");
        if (e.event.ended) return fail(409, "ended", "This event has ended.");
        if (e.event.paused) return fail(409, "paused", "The host has paused check-ins for now.");
        if (e.devices[body.deviceId]) return ok({ attendee: e.devices[body.deviceId], already: true });
        const a = {
          id: `a${e.attendees.length + 1}`,
          name: body.name,
          note: body.note ?? null,
          method: body.tap ? (body.late ? "tap_late" : "tap") : "location",
          distance: body.tap ? null : 12,
          checkedInAt: new Date().toISOString(),
          leftEarlyAt: null,
        };
        e.attendees.push(a);
        e.devices[body.deviceId] = a;
        return ok({ attendee: a });
      }
      case "/leave": {
        const e = db.events[body.code];
        const a = e?.devices[body.deviceId];
        if (!a) return fail(404, "not-checked-in", "You haven't checked in.");
        a.leftEarlyAt = new Date().toISOString();
        return ok({ attendee: a });
      }
      case "/unlock": {
        const e = db.events[body.code];
        if (!e) return fail(404, "not-found", "No event with that code.");
        if (!e.password || e.password !== body.password) return fail(403, "wrong-password", "That password isn't right.");
        return ok({ hostKey: e.hostKey, ...snapshot(e) });
      }
      case "/host": {
        const e = db.events[body.code];
        if (!e) return fail(404, "not-found", "No event with that code.");
        if (body.hostKey !== e.hostKey) return fail(403, "not-host", "This device can't manage this event.");
        const now = new Date().toISOString();
        switch (body.action) {
          case "get":
            return ok(snapshot(e));
          case "add":
          case "record": {
            if (e.event.ended) return fail(409, "ended", "This event has ended.");
            const a = {
              id: `a${e.attendees.length + 1}`,
              name: body.name,
              note: body.note ?? null,
              method: body.action === "add" ? "manual" : body.method || "p2p",
              distance: null,
              checkedInAt: body.at || now,
              leftEarlyAt: null,
            };
            e.attendees.push(a);
            return ok({ attendee: a });
          }
          case "remove":
            e.attendees = e.attendees.filter((a) => a.id !== body.attendeeId);
            return ok(snapshot(e));
          case "pause":
          case "resume":
            e.event.paused = body.action === "pause";
            return ok(snapshot(e));
          case "update":
            Object.assign(e.event, body.settings, { hasLocation: e.event.hasLocation || Boolean(body.settings.location) });
            delete e.event.location;
            return ok(snapshot(e));
          case "password":
            e.password = body.password || null;
            e.event.hasPassword = Boolean(body.password);
            return ok(snapshot(e));
          case "end":
            e.event.ended = true;
            e.event.endedAt = now;
            return ok(snapshot(e));
        }
        return fail(400, "bad-action", "Unknown action.");
      }
      default:
        return raw(404, { ok: false, error: "Not found", reason: "not-found" });
    }
  });
  return db;
}

/**
 * Values put in the app's store before it opens, under the site's keys (store.dart's "ls."
 * prefix, as shared_preferences keeps them in a browser). Tours are marked seen unless `tours`.
 * Values are JSON-encoded as the site's store.js writes them, except plain strings given as such.
 */
export async function seed(page, values = {}, { tours = false } = {}) {
  await page.addInitScript(
    ([values, tours]) => {
      if (sessionStorage.getItem("seeded")) return;
      sessionStorage.setItem("seeded", "1");
      const put = (k, v) => localStorage.setItem(`flutter.ls.${k}`, JSON.stringify(typeof v === "string" ? v : JSON.stringify(v)));
      if (!tours) {
        put("uwuhere.tour.welcome", "done");
        put("uwuhere.tour.pages", ["host", "join"]);
      }
      for (const [k, v] of Object.entries(values)) put(k, v);
    },
    [values, tours],
  );
}

/** What a device that hosts these events keeps (store.js's uwuhere.hosted). */
export const hosted = (...events) =>
  Object.fromEntries(events.map((e) => [e.event.code, { hostKey: e.hostKey, title: e.event.title, createdAt: e.event.createdAt, ended: e.event.ended }]));

/**
 * In a browser, each slider leaves an empty, nameless layer over the whole window (where its value
 * bubble would show), and Playwright takes it for something in the way of every click. Clicks go
 * through such layers here, as they do for a finger.
 */
export async function passThroughEmptyLayers(page) {
  await page.addInitScript(() => {
    const add = () => {
      const style = document.createElement("style");
      style.textContent = "flt-semantics:empty:not([role]):not([aria-label]) { pointer-events: none !important; }";
      document.head.appendChild(style);
    };
    if (document.head) add();
    else document.addEventListener("DOMContentLoaded", add);
  });
}

/** The app, up, with the errors it logs collected. `query` like "?android=1". */
export async function openApp(page, query = "", { ready } = {}) {
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("console", (m) => {
    if (m.type() === "error" && !/favicon|Failed to load resource|peerjs|WebSocket|ERR_INTERNET_DISCONNECTED/i.test(m.text())) errors.push(m.text());
  });
  await passThroughEmptyLayers(page);
  await page.goto(`/${query}`);
  page.appErrors = errors;
  await expect(ready ? ready(page) : page.getByRole("heading", { name: /Checking in\?|Host an event/ }).first()).toBeVisible({ timeout: 30_000 });
  return errors;
}

export const button = (page, name, exact = true) => page.getByRole("button", { name, exact });

/** What the app keeps, as shared_preferences has it in the browser. */
export const stored = (page, key) =>
  page.evaluate((k) => {
    const v = localStorage.getItem(`flutter.ls.${k}`);
    return v === null ? null : JSON.parse(v);
  }, key);

export const storedJson = async (page, key) => {
  const v = await stored(page, key);
  return v == null ? null : JSON.parse(v);
};

/** What the app asked of its Android side. */
export const calls = (page) => page.evaluate(() => Array.from(window.e2eCalls || []).map((c) => JSON.parse(c)));

/** Says what Android would have said. */
export const emit = (page, plugin, event, data) => page.evaluate(([p, e, d]) => window.e2eEmit(p, e, JSON.stringify(d)), [plugin, event, data]);

/** Types into a text field. */
export async function fill(page, locator, text) {
  await locator.click();
  await page.waitForTimeout(200);
  await page.keyboard.press("Control+A");
  await page.keyboard.type(text);
}

/** A tour on screen goes. */
export async function skipTour(page) {
  const skip = button(page, "Skip");
  try {
    await skip.waitFor({ timeout: 3500 });
    await skip.click();
  } catch {
    // None this time.
  }
}

/** Nothing went wrong. `offline`: the browser's own bare "Error" for each request that failed. */
export function noErrors(page, { offline = false } = {}) {
  expect(page.appErrors.filter((e) => !/WebSocket|peerjs|broker|ERR_INTERNET_DISCONNECTED/i.test(e) && !(offline && e === "Error"))).toEqual([]);
}

/** A toast or note: said once to a screen reader and once on screen, so the one on screen. */
export const said = (page, text) => page.getByText(text).last();

/**
 * Brings something on a scrolling page into view: Flutter draws only what's near the screen, so
 * it's scrolled with the mouse wheel over the page till it's there.
 */
export async function reveal(page, locator, { x } = {}) {
  const size = page.viewportSize();
  await page.mouse.move(x ?? size.width / 2, size.height * 0.6);
  for (let i = 0; i < 40; i++) {
    if ((await locator.count()) && (await locator.first().isVisible())) {
      const box = await locator.first().boundingBox();
      if (box && box.y >= 0 && box.y + box.height <= size.height) return locator.first();
    }
    await page.mouse.wheel(0, 250);
    await page.waitForTimeout(120);
  }
  return locator.first();
}
