import { expect, test } from "@playwright/test";
import { button, calls, emit, fill, hosted, makeEvent, mockApi, noErrors, openApp, reveal, said, seed, storedJson } from "./helpers.js";

const hostReady = (title) => (p) => p.getByRole("heading", { name: title });

// What only the phone does for a host (the Here plugin: TapService, Mesh, Hotspot), reached
// through the bridge as MainActivity.java answers it.
test("host on Android: taps, Bluetooth and the hotspot ready; check-ins from Bluetooth and the hotspot recorded", async ({ page }) => {
  const db = await mockApi(page);
  const e = makeEvent(db, { title: "Gym class", allowTap: true, allowBluetooth: true, allowLocation: false });
  await seed(page, { "uwuhere.hosted": hosted(e) });
  await openApp(page, `?android=1&page=host&id=${e.event.code}`, { ready: hostReady("Gym class") });

  await expect(page.getByText("Ready for taps. People hold their phone against the back of this one.").first()).toBeVisible();
  await expect(page.getByText(/^Ready for Bluetooth\./).first()).toBeVisible();
  const tap = (await calls(page)).find((c) => c.method === "tap" && c.options.on);
  expect(tap.options).toEqual({ on: true, code: e.event.code, hostKey: e.hostKey });
  // The event's own check-in topic and the home screen widget, told.
  await expect.poll(async () => (await calls(page)).some((c) => c.method === "watchEvent" && /^uwuhere-host-[0-9a-f]{40}$/.test(c.options.topic))).toBe(true);
  await expect.poll(async () => (await calls(page)).find((c) => c.method === "widget")?.options).toMatchObject({ code: e.event.code, count: 0 });

  // Someone touches the host's phone.
  await emit(page, "Here", "tapped", {});
  await expect(said(page, "Phone tapped. They finish on their phone.")).toBeVisible();

  // A Bluetooth check-in from an attendee's app: recorded, and answered.
  await emit(page, "Here", "meshCheckin", { id: "m1", name: "Robin", note: null, deviceHash: "b".repeat(64) });
  await expect(page.getByText("Robin", { exact: true }).first()).toBeVisible();
  await expect.poll(async () => (await calls(page)).find((c) => c.method === "meshAnswer")?.options).toMatchObject({ id: "m1", ok: true });
  expect(e.attendees.at(-1)).toMatchObject({ name: "Robin", method: "mesh" });

  // The hotspot: its two codes, at full brightness.
  await (await reveal(page, button(page, "Start"))).click();
  await expect(page.getByRole("heading", { name: "Check in without internet" })).toBeVisible();
  await expect(page.getByText("Wifi: uwuHere-K7Q2, password blue-otter-41").first()).toBeVisible();
  await expect.poll(async () => (await calls(page)).some((c) => c.method === "brightness" && c.options.max === true)).toBe(true);
  await emit(page, "Here", "hotspotCheckin", { id: "h1", name: "Kim", note: null, deviceHash: "c".repeat(64) });
  await expect.poll(async () => (await calls(page)).find((c) => c.method === "hotspotAnswer")?.options).toMatchObject({ id: "h1", ok: true });
  expect(e.attendees.at(-1)).toMatchObject({ name: "Kim", method: "hotspot" });
  await button(page, "Stop the hotspot").click();
  await expect(await reveal(page, page.getByText("No internet for attendees? This phone can be their wifi."))).toBeVisible();
  noErrors(page);
});

test("host on Android with no NFC says so", async ({ page }) => {
  const db = await mockApi(page);
  const e = makeEvent(db, { title: "Quiz", allowTap: true, allowLocation: false, allowP2p: false });
  await seed(page, { "uwuhere.hosted": hosted(e) });
  await openApp(page, `?android=1&nonfc=1&page=host&id=${e.event.code}`, { ready: hostReady("Quiz") });
  await expect(page.getByText(/This phone can't take taps: it has no NFC/).first()).toBeVisible();
  noErrors(page);
});

// A host's phone hands over its link with a one-time token, which Android opens in the app: with
// the name already kept, it checks in by itself.
test("a tap opens the check-in page and checks in by itself with the name kept", async ({ page }) => {
  const db = await mockApi(page);
  const e = makeEvent(db, { title: "Seminar", allowTap: true, allowLocation: false });
  await seed(page, { "uwuhere.profile": { name: "Ari", note: "" } });
  await openApp(page, "?android=1");
  await emit(page, "App", "link", { url: `https://here.uwuapps.org/join?id=${e.event.code}&tap=1763251200.abcdefgh.signature0` });
  await expect(page.getByRole("heading", { name: "Seminar" })).toBeVisible();
  await expect(said(page, "You're checked in.")).toBeVisible();
  expect(db.requests.find((r) => r.path === "/checkin").body).toMatchObject({ code: e.event.code, name: "Ari", tap: "1763251200.abcdefgh.signature0" });
  expect(e.attendees[0]).toMatchObject({ name: "Ari", method: "tap" });
  noErrors(page);
});

// Bluetooth, attendee side: the app finds the host's phone (Mesh.java), no internet needed.
test("check in by Bluetooth in the app", async ({ page }) => {
  const db = await mockApi(page);
  const e = makeEvent(db, { title: "Workshop", allowBluetooth: true, allowLocation: false });
  await seed(page, { "uwuhere.profile": { name: "Noor", note: "" } });
  await openApp(page, `?android=1&page=join&id=${e.event.code}`, { ready: (p) => p.getByRole("heading", { name: "Workshop" }) });
  await expect(page.getByText(/Bluetooth, phone to phone with the host/).first()).toBeVisible();
  await button(page, "I'm here").click();
  await expect(said(page, "You're checked in.")).toBeVisible();
  const mesh = (await calls(page)).find((c) => c.method === "meshCheckIn");
  expect(mesh.options).toMatchObject({ code: e.event.code, name: "Noor" });
  expect(mesh.options.deviceHash).toMatch(/^[0-9a-f]{64}$/);
  expect((await storedJson(page, `uwuhere.attend.${e.event.code}`)).method).toBe("mesh");
  noErrors(page);
});

// The host offline: a check-in is kept on the phone, said "Not sent yet", and sent when it's back.
test("offline on the host: a check-in waits in the outbox and is sent once back online", async ({ page }) => {
  const db = await mockApi(page);
  const e = makeEvent(db, { title: "Field trip", allowBluetooth: true, allowLocation: false });
  await seed(page, { "uwuhere.hosted": hosted(e) });
  await openApp(page, `?android=1&page=host&id=${e.event.code}`, { ready: hostReady("Field trip") });
  db.offline = true;
  await emit(page, "Here", "meshCheckin", { id: "m9", name: "Lou", note: null, deviceHash: "d".repeat(64) });
  await expect(page.getByText("Not sent yet").first()).toBeVisible();
  await expect.poll(async () => (await calls(page)).find((c) => c.method === "meshAnswer")?.options.ok).toBe(true);
  expect((await storedJson(page, `uwuhere.outbox.${e.event.code}`)).length).toBe(1);
  await expect(page.getByText(/^Offline\. Showing the list from/).first()).toBeVisible();
  db.offline = false;
  await expect(page.getByText("Not sent yet")).toHaveCount(0, { timeout: 30_000 });
  expect(e.attendees.at(-1)).toMatchObject({ name: "Lou", method: "mesh" });
  expect(await storedJson(page, `uwuhere.outbox.${e.event.code}`)).toBeNull();
  noErrors(page, { offline: true });
});

// The bell: three switches, each a set of FCM topics joined by the app.
test("notifications: the bell's switches join their topics", async ({ page }) => {
  await mockApi(page);
  await seed(page);
  await openApp(page, "?android=1");
  await button(page, "Notifications").click();
  await expect(page.getByRole("heading", { name: "Notifications" })).toBeVisible();
  await page.getByRole("switch", { name: /Check-ins to my events/ }).click();
  await expect.poll(async () => (await calls(page)).find((c) => c.method === "setTopic")?.options).toEqual({ topic: "checkins", on: true });
  await page.getByRole("switch", { name: /News from uwuHere/ }).click();
  await expect.poll(async () => (await calls(page)).filter((c) => c.method === "setTopic").length).toBe(2);
  noErrors(page);
});

// The site's #join, from the "Check in" widget: the code box, focused.
test("the Check in widget's link lands on the code box", async ({ page }) => {
  await mockApi(page);
  await seed(page);
  await openApp(page, "?android=1");
  await emit(page, "App", "link", { url: "https://here.uwuapps.org/#join" });
  await expect(page.getByRole("textbox", { name: "Event code" })).toBeFocused();
  await page.keyboard.type("bcd234");
  await expect(page.getByRole("textbox", { name: "Event code" })).toHaveValue("BCD234");
  noErrors(page);
});
