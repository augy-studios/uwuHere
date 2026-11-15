import { expect, test } from "@playwright/test";
import { button, fill, hosted, makeEvent, mockApi, noErrors, openApp, reveal, said, seed, stored, storedJson } from "./helpers.js";

test.use({ geolocation: { latitude: 1.3521, longitude: 103.8198 }, permissions: ["geolocation"] });

// The home page's form (index.html, js/home.js): an event made by location, then its host page.
test("make an event, then run it from its host page: add by hand, pause, settings, CSV, end", async ({ page }) => {
  const db = await mockApi(page);
  await seed(page);
  await openApp(page);

  const name = page.getByRole("textbox", { name: "Event name" });
  await fill(page, await reveal(page, name), "Weekly meetup");
  await fill(page, await reveal(page, page.getByRole("textbox", { name: "Button text" })), "Present!");
  // Same wifi off (it needs PeerJS's broker), location on.
  await (await reveal(page, page.getByRole("switch", { name: "Same wifi" }))).click();
  await (await reveal(page, page.getByRole("switch", { name: "Location" }))).click();
  await expect(page.getByText(/Location: attendees share their location once/).first()).toBeVisible();
  // A weak password says why, and nothing is made.
  await fill(page, await reveal(page, page.getByRole("textbox", { name: "Password" })), "qwertyuiopasdf");
  await expect(page.getByText(/Not a repeat or a run like 12345 or qwerty/).first()).toBeVisible();
  await (await reveal(page, page.getByRole("button", { name: "Create event" }))).click();
  await expect(said(page, "That password is not strong enough yet. See the checklist under it.")).toBeVisible();
  await fill(page, page.getByRole("textbox", { name: "Password" }), "correct horse battery staple");
  await (await reveal(page, page.getByRole("button", { name: "Create event" }))).click();

  // The host page: its code, the QR code and the link.
  await expect(page.getByRole("heading", { name: "Weekly meetup" })).toBeVisible();
  const code = Object.keys(db.events)[0];
  await expect(page.getByRole("button", { name: new RegExp(`^Event code ${code.split("").join(" ")}`) })).toBeVisible();
  await expect(page.getByText(`https://here.uwuapps.org/join?id=${code}`).first()).toBeVisible();
  const made = db.requests.find((r) => r.path === "/events").body;
  expect(made).toMatchObject({ title: "Weekly meetup", buttonLabel: "Present!", allowP2p: false, allowLocation: true, radius: 100 });
  expect(made.location).toMatchObject({ lat: 1.3521, lng: 103.8198 });
  // Kept as the site keeps it: the host key under uwuhere.hosted.
  expect((await storedJson(page, "uwuhere.hosted"))[code].hostKey).toBe(db.events[code].hostKey);
  await expect(page.getByText(/Location check-in within 100 m/).first()).toBeVisible();

  // Added by hand.
  await fill(page, await reveal(page, page.getByRole("textbox", { name: "Name to add by hand" })), "Sam Lee");
  await button(page, "Add").click();
  await expect(page.getByText("Sam Lee", { exact: true }).first()).toBeVisible();
  await expect(page.getByText("1 checked in").first()).toBeVisible();

  // Someone checks in by location meanwhile: the list polls.
  db.events[code].attendees.push({ id: "x1", name: "Alex Tan", note: null, method: "location", distance: 23, checkedInAt: new Date().toISOString(), leftEarlyAt: null });
  await expect(page.getByText("Alex Tan", { exact: true }).first()).toBeVisible({ timeout: 10_000 });
  await expect(page.getByText("2 checked in").first()).toBeVisible();

  // Pause, and back.
  await (await reveal(page, button(page, "Pause"))).click();
  await expect(page.getByText("Check-ins are paused. Nobody new can check in until you resume.").first()).toBeVisible();
  expect(db.events[code].event.paused).toBe(true);
  await (await reveal(page, button(page, "Resume"))).click();
  await expect(page.getByText("Check-ins are paused.")).toHaveCount(0);

  // Settings, from the Edge Tray: a new name.
  await button(page, "Event settings").click();
  await expect(page.getByRole("heading", { name: "Event settings" })).toBeVisible();
  await fill(page, page.getByRole("textbox", { name: "Event name" }).last(), "Monday meetup");
  await (await reveal(page, button(page, "Save"))).click();
  await expect(said(page, "Saved")).toBeVisible();
  await expect(page.getByRole("heading", { name: "Monday meetup" })).toBeVisible();

  // The CSV: a download, with a formula in a name defused.
  db.events[code].attendees.push({ id: "x2", name: "=SUM(A1)", note: null, method: "manual", distance: null, checkedInAt: new Date().toISOString(), leftEarlyAt: null });
  await page.waitForTimeout(6000);
  const download = page.waitForEvent("download");
  await (await reveal(page, button(page, "CSV"))).click();
  const file = await download;
  expect(file.suggestedFilename()).toMatch(new RegExp(`^uwuhere-${code}-\\d{4}-\\d{2}-\\d{2}\\.csv$`));
  const csv = await (await file.createReadStream()).toArray().then((c) => Buffer.concat(c).toString("utf8"));
  expect(csv.startsWith("\uFEFFName,Note,Checked in,How,Distance (m),Left early")).toBe(true);
  expect(csv).toContain("Alex Tan");
  expect(csv).toContain("Location,23");
  expect(csv).toContain("'=SUM(A1)");

  // End it.
  await (await reveal(page, button(page, "End event"))).click();
  await expect(page.getByRole("heading", { name: "End this event?" })).toBeVisible();
  await button(page, "End event").last().click();
  await expect(said(page, "Event ended")).toBeVisible();
  await expect(page.getByText(/^Ended .*The list can be downloaded here until/).first()).toBeVisible();
  expect(db.events[code].event.ended).toBe(true);
  noErrors(page);
});

// The check-in page (join.html, js/join.js): by location, once, then leaving early.
test("check in by location, once; leave early; the name is kept for next time", async ({ page }) => {
  const db = await mockApi(page);
  const e = makeEvent(db, { title: "Book club", buttonLabel: "Here!", buttonColor: "#336699", noteLabel: "Student ID" });
  await seed(page);
  await openApp(page, `?page=join&id=${e.event.code}`, { ready: (p) => p.getByRole("heading", { name: "Book club" }) });
  await expect(page.getByText(/Checks that you are here by being within 100 m of the host/).first()).toBeVisible();

  // No name: asks for one.
  await button(page, "Here!").click();
  await expect(said(page, "Type your name first.")).toBeVisible();

  await fill(page, page.getByRole("textbox", { name: "Your name" }), "Jo Lim");
  await fill(page, page.getByRole("textbox", { name: "Student ID" }), "A0123");
  await button(page, "Here!").click();
  await expect(said(page, "You're checked in.")).toBeVisible();
  await expect(page.getByText("Checked in as Jo Lim.").first()).toBeVisible();
  const sent = db.requests.find((r) => r.path === "/checkin").body;
  expect(sent).toMatchObject({ code: e.event.code, name: "Jo Lim", note: "A0123" });
  expect(sent.position).toMatchObject({ lat: 1.3521, lng: 103.8198 });
  expect(e.attendees).toHaveLength(1);
  expect((await storedJson(page, `uwuhere.attend.${e.event.code}`)).checkedInAt).toBeTruthy();
  expect(await storedJson(page, "uwuhere.profile")).toEqual({ name: "Jo Lim", note: "A0123" });

  // Leaving early: once.
  await button(page, "I'm leaving early").click();
  await expect(page.getByRole("heading", { name: "Leaving early?" })).toBeVisible();
  await button(page, "I'm leaving").click();
  await expect(said(page, "The host can see you left early")).toBeVisible();
  await expect(page.getByRole("button", { name: /^Left at \d\d:\d\d/ })).toBeDisabled();
  expect(e.attendees[0].leftEarlyAt).toBeTruthy();
  noErrors(page);
});

test("a code that isn't one says so; an event that's gone says so", async ({ page }) => {
  await mockApi(page);
  await seed(page);
  await openApp(page);
  await fill(page, page.getByRole("textbox", { name: "Event code" }), "ABC");
  await button(page, "Join").click();
  await expect(said(page, "An event code is 6 letters and numbers, like BCD234.")).toBeVisible();
  await fill(page, page.getByRole("textbox", { name: "Event code" }), "bcd234");
  await button(page, "Join").click();
  await expect(page.getByRole("heading", { name: "No event with that code" })).toBeVisible();
  noErrors(page);
});

// Opening an event on another device, with its password; and forgetting one on this device.
test("open an event you host elsewhere with its password; forget one here", async ({ page }) => {
  const db = await mockApi(page);
  const e = makeEvent(db, { title: "Choir", password: "correct horse battery staple", hasPassword: true });
  const mine = makeEvent(db, { title: "Old event" });
  await seed(page, { "uwuhere.hosted": hosted(mine) });
  await openApp(page);
  await expect(page.getByRole("group", { name: /^Old event/ })).toBeVisible();

  await fill(page, page.getByRole("textbox", { name: "Code of an event you host" }), e.event.code);
  await button(page, "Open").click();
  await expect(page.getByRole("heading", { name: "Open this event" })).toBeVisible();
  await fill(page, page.getByRole("textbox", { name: "Event password" }), "wrong one at all here");
  await page.keyboard.press("Enter");
  await expect(said(page, "That password isn't right.")).toBeVisible();
  await fill(page, page.getByRole("textbox", { name: "Event password" }), "correct horse battery staple");
  await page.keyboard.press("Enter");
  await expect(page.getByRole("heading", { name: "Choir" })).toBeVisible();
  expect((await storedJson(page, "uwuhere.hosted"))[e.event.code].hostKey).toBe(e.hostKey);

  // Home, and forget the old one: two presses.
  await button(page, "Home").click();
  const forget = page.getByRole("button", { name: new RegExp(`^Forget ${mine.event.code} on this device`) });
  await forget.click();
  await button(page, "Forget?").click();
  await expect(page.getByRole("group", { name: /^Old event/ })).toHaveCount(0);
  expect(Object.keys(await storedJson(page, "uwuhere.hosted"))).toEqual([e.event.code]);
  expect(await stored(page, `uwuhere.host.${mine.event.code}`)).toBeNull();
  noErrors(page);
});
