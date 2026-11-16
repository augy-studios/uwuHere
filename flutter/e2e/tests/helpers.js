import { expect } from "@playwright/test";

export const API = "https://here.uwuapps.org/api";

let counter = 0;
const CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXYZ23456789";

/** A six-character event code made from the counter, so each test run gets the same codes. */
const newCode = () => {
  return Array.from({ length: 6 }, (unusedValue, characterIndex) => {
    return CODE_ALPHABET[(counter * 7 + characterIndex * 11 + 3) % CODE_ALPHABET.length];
  }).join("");
};

/** A 43-character host key made from the code, padded with "k". */
const hostKeyFor = (code) => {
  return `${code}`.padEnd(43, "k").slice(0, 43);
};

/** An event as the server keeps it, in database.events[code]. */
export function makeEvent(database, fields = {}) {
  counter = counter + 1;
  let code = fields.code;
  if (code === null || code === undefined) {
    code = newCode();
  }
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
  let password = fields.password;
  if (password === null || password === undefined) {
    password = null;
  }
  database.events[code] = { event, attendees: [], hostKey: hostKeyFor(code), password, devices: {} };
  return database.events[code];
}

/**
 * uwuHere's API (main-site/api/*), answered here from an in-memory store, so the suite runs
 * offline and the same every time: events, the host's actions, check-ins by location and by tap,
 * leaving early, unlocking with a password, the release check and Report a bug. Every request is
 * kept in `database.requests`.
 */
export async function mockApi(page, database = {}) {
  database.requests = [];
  if (database.events === null || database.events === undefined) {
    database.events = {};
  }
  if (database.release === null || database.release === undefined) {
    database.release = { version: null, history: [] };
  }
  await page.route(`${API}/**`, async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^\/api/, "");
    let body = null;
    if (request.postData()) {
      body = JSON.parse(request.postData());
    }
    database.requests.push({ method: request.method(), path, body, query: Object.fromEntries(url.searchParams) });
    const headers = { "access-control-allow-origin": "*", "access-control-allow-headers": "*" };
    const respond = (status, data) => {
      return route.fulfill({ status, contentType: "application/json", headers, body: JSON.stringify(data) });
    };
    const respondOk = (data) => {
      return respond(200, { ok: true, data });
    };
    const respondFail = (status, reason, error) => {
      return respond(status, { ok: false, reason, error });
    };
    if (request.method() === "OPTIONS") {
      return route.fulfill({ status: 204, headers: { ...headers, "access-control-allow-methods": "*" } });
    }
    if (database.offline) {
      return route.abort("internetdisconnected");
    }
    const snapshot = (eventRecord) => {
      return { event: eventRecord.event, attendees: eventRecord.attendees };
    };
    switch (path) {
      case "/app-release":
        return respond(200, database.release);
      case "/bug-report":
        if (database.bugReports === null || database.bugReports === undefined) {
          database.bugReports = [];
        }
        database.bugReports.push(body);
        if (database.bugStatus && database.bugStatus !== 200) {
          return respond(database.bugStatus, { error: "Bug reports can't be sent from the app yet." });
        }
        return respond(200, { id: "20261116-7K3Q" });
      case "/events": {
        let title = body.title;
        if (title === null || title === undefined) {
          title = "";
        }
        let noteLabel = body.noteLabel;
        if (!noteLabel) {
          noteLabel = null;
        }
        let password = body.password;
        if (password === null || password === undefined) {
          password = null;
        }
        const eventRecord = makeEvent(database, {
          title,
          buttonLabel: body.buttonLabel,
          buttonColor: body.buttonColor,
          noteLabel,
          allowP2p: body.allowP2p,
          allowLocation: body.allowLocation,
          allowTap: body.allowTap,
          allowBluetooth: body.allowBluetooth,
          radius: body.radius,
          hasLocation: Boolean(body.location),
          hasPassword: Boolean(body.password),
          password,
        });
        return respondOk({ code: eventRecord.event.code, hostKey: eventRecord.hostKey, ...snapshot(eventRecord) });
      }
      case "/event": {
        const eventRecord = database.events[url.searchParams.get("code")];
        if (!eventRecord) {
          return respondFail(404, "not-found", "No event with that code.");
        }
        // Everything but hasPassword is what anyone may see.
        const { hasPassword, ...publicFields } = eventRecord.event;
        const device = request.headers()["x-uwuhere-device"];
        let myCheckIn = device;
        if (device) {
          myCheckIn = eventRecord.devices[device];
        }
        let me = null;
        if (myCheckIn) {
          me = { checkedInAt: myCheckIn.checkedInAt, leftEarlyAt: myCheckIn.leftEarlyAt };
        }
        return respondOk({ ...publicFields, me });
      }
      case "/checkin": {
        const eventRecord = database.events[body.code];
        if (!eventRecord) {
          return respondFail(404, "not-found", "No event with that code.");
        }
        if (eventRecord.event.ended) {
          return respondFail(409, "ended", "This event has ended.");
        }
        if (eventRecord.event.paused) {
          return respondFail(409, "paused", "The host has paused check-ins for now.");
        }
        if (eventRecord.devices[body.deviceId]) {
          return respondOk({ attendee: eventRecord.devices[body.deviceId], already: true });
        }
        let note = body.note;
        if (note === null || note === undefined) {
          note = null;
        }
        let method;
        if (body.tap) {
          if (body.late) {
            method = "tap_late";
          } else {
            method = "tap";
          }
        } else {
          method = "location";
        }
        let distance;
        if (body.tap) {
          distance = null;
        } else {
          distance = 12;
        }
        const attendee = {
          id: `a${eventRecord.attendees.length + 1}`,
          name: body.name,
          note,
          method,
          distance,
          checkedInAt: new Date().toISOString(),
          leftEarlyAt: null,
        };
        eventRecord.attendees.push(attendee);
        eventRecord.devices[body.deviceId] = attendee;
        return respondOk({ attendee });
      }
      case "/leave": {
        const eventRecord = database.events[body.code];
        let attendee;
        if (eventRecord === null || eventRecord === undefined) {
          attendee = undefined;
        } else {
          attendee = eventRecord.devices[body.deviceId];
        }
        if (!attendee) {
          return respondFail(404, "not-checked-in", "You haven't checked in.");
        }
        attendee.leftEarlyAt = new Date().toISOString();
        return respondOk({ attendee });
      }
      case "/unlock": {
        const eventRecord = database.events[body.code];
        if (!eventRecord) {
          return respondFail(404, "not-found", "No event with that code.");
        }
        if (!eventRecord.password || eventRecord.password !== body.password) {
          return respondFail(403, "wrong-password", "That password isn't right.");
        }
        return respondOk({ hostKey: eventRecord.hostKey, ...snapshot(eventRecord) });
      }
      case "/host": {
        const eventRecord = database.events[body.code];
        if (!eventRecord) {
          return respondFail(404, "not-found", "No event with that code.");
        }
        if (body.hostKey !== eventRecord.hostKey) {
          return respondFail(403, "not-host", "This device can't manage this event.");
        }
        const now = new Date().toISOString();
        switch (body.action) {
          case "get":
            return respondOk(snapshot(eventRecord));
          case "add":
          case "record": {
            if (eventRecord.event.ended) {
              return respondFail(409, "ended", "This event has ended.");
            }
            let note = body.note;
            if (note === null || note === undefined) {
              note = null;
            }
            let method;
            if (body.action === "add") {
              method = "manual";
            } else if (body.method) {
              method = body.method;
            } else {
              method = "p2p";
            }
            let checkedInAt = body.at;
            if (!checkedInAt) {
              checkedInAt = now;
            }
            const attendee = {
              id: `a${eventRecord.attendees.length + 1}`,
              name: body.name,
              note,
              method,
              distance: null,
              checkedInAt,
              leftEarlyAt: null,
            };
            eventRecord.attendees.push(attendee);
            return respondOk({ attendee });
          }
          case "remove":
            eventRecord.attendees = eventRecord.attendees.filter((attendee) => {
              return attendee.id !== body.attendeeId;
            });
            return respondOk(snapshot(eventRecord));
          case "pause":
          case "resume":
            eventRecord.event.paused = body.action === "pause";
            return respondOk(snapshot(eventRecord));
          case "update": {
            let hasLocation = eventRecord.event.hasLocation;
            if (!hasLocation) {
              hasLocation = Boolean(body.settings.location);
            }
            Object.assign(eventRecord.event, body.settings, { hasLocation });
            delete eventRecord.event.location;
            return respondOk(snapshot(eventRecord));
          }
          case "password":
            if (body.password) {
              eventRecord.password = body.password;
            } else {
              eventRecord.password = null;
            }
            eventRecord.event.hasPassword = Boolean(body.password);
            return respondOk(snapshot(eventRecord));
          case "end":
            eventRecord.event.ended = true;
            eventRecord.event.endedAt = now;
            return respondOk(snapshot(eventRecord));
        }
        return respondFail(400, "bad-action", "Unknown action.");
      }
      default:
        return respond(404, { ok: false, error: "Not found", reason: "not-found" });
    }
  });
  return database;
}

/**
 * Values put in the app's store before it opens, under the site's keys (store.dart's "ls."
 * prefix, as shared_preferences keeps them in a browser). Tours are marked seen unless `tours`.
 * Values are JSON-encoded as the site's store.js writes them, except plain strings given as such.
 */
export async function seed(page, values = {}, { tours = false } = {}) {
  await page.addInitScript(
    ([valuesToStore, showTours]) => {
      if (sessionStorage.getItem("seeded")) {
        return;
      }
      sessionStorage.setItem("seeded", "1");
      const put = (key, value) => {
        let encoded;
        if (typeof value === "string") {
          encoded = value;
        } else {
          encoded = JSON.stringify(value);
        }
        localStorage.setItem(`flutter.ls.${key}`, JSON.stringify(encoded));
      };
      if (!showTours) {
        put("uwuhere.tour.welcome", "done");
        put("uwuhere.tour.pages", ["host", "join"]);
      }
      for (const [key, value] of Object.entries(valuesToStore)) {
        put(key, value);
      }
    },
    [values, tours],
  );
}

/** What a device that hosts these events keeps (store.js's uwuhere.hosted). */
export const hosted = (...events) => {
  const entries = events.map((eventRecord) => {
    return [
      eventRecord.event.code,
      { hostKey: eventRecord.hostKey, title: eventRecord.event.title, createdAt: eventRecord.event.createdAt, ended: eventRecord.event.ended },
    ];
  });
  return Object.fromEntries(entries);
};

/**
 * In a browser, each slider leaves an empty, nameless layer over the whole window (where its value
 * bubble would show), and Playwright takes it for something in the way of every click. Clicks go
 * through such layers here, as they do for a finger.
 */
export async function passThroughEmptyLayers(page) {
  await page.addInitScript(() => {
    const addStyle = () => {
      const style = document.createElement("style");
      style.textContent = "flt-semantics:empty:not([role]):not([aria-label]) { pointer-events: none !important; }";
      document.head.appendChild(style);
    };
    if (document.head) {
      addStyle();
    } else {
      document.addEventListener("DOMContentLoaded", addStyle);
    }
  });
}

/** The app, up, with the errors it logs collected. `query` like "?android=1". */
export async function openApp(page, query = "", { ready } = {}) {
  const errors = [];
  page.on("pageerror", (error) => {
    errors.push(String(error));
  });
  page.on("console", (message) => {
    if (message.type() === "error" && !/favicon|Failed to load resource|peerjs|WebSocket|ERR_INTERNET_DISCONNECTED/i.test(message.text())) {
      errors.push(message.text());
    }
  });
  await passThroughEmptyLayers(page);
  await page.goto(`/${query}`);
  page.appErrors = errors;
  let readyLocator;
  if (ready) {
    readyLocator = ready(page);
  } else {
    readyLocator = page.getByRole("heading", { name: /Checking in\?|Host an event/ }).first();
  }
  await expect(readyLocator).toBeVisible({ timeout: 30_000 });
  return errors;
}

export const button = (page, name, exact = true) => {
  return page.getByRole("button", { name, exact });
};

/** What the app keeps, as shared_preferences has it in the browser. */
export const stored = (page, key) => {
  return page.evaluate((storeKey) => {
    const value = localStorage.getItem(`flutter.ls.${storeKey}`);
    if (value === null) {
      return null;
    }
    return JSON.parse(value);
  }, key);
};

/** What the app keeps under `key`, read back from the JSON text it was stored as. */
export const storedJson = async (page, key) => {
  const value = await stored(page, key);
  if (value === null || value === undefined) {
    return null;
  }
  return JSON.parse(value);
};

/** What the app asked of its Android side. */
export const calls = (page) => {
  return page.evaluate(() => {
    let recordedCalls = window.e2eCalls;
    if (!recordedCalls) {
      recordedCalls = [];
    }
    return Array.from(recordedCalls).map((callJson) => {
      return JSON.parse(callJson);
    });
  });
};

/** Says what Android would have said. */
export const emit = (page, plugin, event, data) => {
  return page.evaluate(
    ([pluginName, eventName, eventData]) => {
      return window.e2eEmit(pluginName, eventName, JSON.stringify(eventData));
    },
    [plugin, event, data],
  );
};

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
  const unexpectedErrors = page.appErrors.filter((error) => {
    const isConnectionNoise = /WebSocket|peerjs|broker|ERR_INTERNET_DISCONNECTED/i.test(error);
    const isOfflineRequestError = offline && error === "Error";
    return !isConnectionNoise && !isOfflineRequestError;
  });
  expect(unexpectedErrors).toEqual([]);
}

/** A toast or note: said once to a screen reader and once on screen, so the one on screen. */
export const said = (page, text) => {
  return page.getByText(text).last();
};

/**
 * Brings something on a scrolling page into view: Flutter draws only what's near the screen, so
 * it's scrolled with the mouse wheel over the page till it's there. `pointerX`: where across the
 * page the wheel is turned (the middle unless given).
 */
export async function reveal(page, locator, { pointerX } = {}) {
  const size = page.viewportSize();
  let pointerPositionX = pointerX;
  if (pointerPositionX === null || pointerPositionX === undefined) {
    pointerPositionX = size.width / 2;
  }
  await page.mouse.move(pointerPositionX, size.height * 0.6);
  for (let attempt = 0; attempt < 40; attempt = attempt + 1) {
    if ((await locator.count()) && (await locator.first().isVisible())) {
      const box = await locator.first().boundingBox();
      if (box && box.y >= 0 && box.y + box.height <= size.height) {
        return locator.first();
      }
    }
    await page.mouse.wheel(0, 250);
    await page.waitForTimeout(120);
  }
  return locator.first();
}
