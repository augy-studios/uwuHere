import { expect, test } from "@playwright/test";
import { button, fill, hosted, makeEvent, mockApi, noErrors, openApp, said, seed, stored } from "./helpers.js";

// Report a bug (lib/features/bug/bug_report.dart), as the site's form (main-site/js/bug-report.js):
// the whole page as a screenshot, an ID back, and never an event's name, code or list.
test("Report a bug: what it adds, Screenshot a page takes the whole page, sent with its ID", async ({ page }) => {
  const db = await mockApi(page);
  const e = makeEvent(db, { title: "Secret party" });
  for (let i = 0; i < 25; i++) {
    e.attendees.push({ id: `p${i}`, name: `Guest ${i}`, note: null, method: "manual", distance: null, checkedInAt: new Date().toISOString(), leftEarlyAt: null });
  }
  await seed(page, { "uwuhere.hosted": hosted(e) });
  await openApp(page, `?android=1&page=host&id=${e.event.code}`, { ready: (p) => p.getByRole("heading", { name: "Secret party" }) });
  await button(page, "Report a bug").click();
  await expect(page.getByRole("heading", { name: "Report a bug" })).toBeVisible();
  const details = page.getByText(/^Sent with it, to help find the bug:/);
  await expect(details).toContainText("Android app");
  await expect(details).toContainText("Host page");
  await expect(details).not.toContainText("Secret party");

  await button(page, "Send").click();
  await expect(said(page, "Please say what went wrong first.")).toBeVisible();
  expect(db.bugReports ?? []).toHaveLength(0);

  await fill(page, page.getByRole("textbox", { name: /What went wrong/ }), "The list jumps when someone checks in.");
  await expect.poll(async () => JSON.parse((await stored(page, "uwuhere.bugDraft")) ?? "{}").text).toBe("The list jumps when someone checks in.");

  await button(page, "Screenshot a page").click();
  await expect(page.getByRole("heading", { name: "Report a bug" })).toHaveCount(0);
  await button(page, "Screenshot this page").click();
  await expect(page.getByRole("heading", { name: "Report a bug" })).toBeVisible({ timeout: 30_000 });
  await expect(page.getByRole("img", { name: "Picture 1" })).toBeVisible({ timeout: 20_000 });

  await button(page, "Send").click();
  await expect(said(page, "Sent as report 20261116-7K3Q. Thank you! Augy will look into it.")).toBeVisible();
  const sent = db.bugReports.at(-1);
  expect(sent).toMatchObject({ text: "The list jumps when someone checks in.", platform: "android", page: "Host page", full: [0] });
  // The whole host page, its 25 names and all: far taller than the screen.
  const look = await page.evaluate(async (src) => {
    const i = new Image();
    i.src = src;
    await i.decode();
    return { w: i.naturalWidth, h: i.naturalHeight };
  }, sent.images[0]);
  expect(look.h / look.w).toBeGreaterThan(2.5);
  expect(Object.keys(sent).sort()).toEqual(["contact", "device", "full", "images", "page", "platform", "text", "version", "website"]);
  const words = JSON.stringify({ ...sent, images: [] });
  expect(words).not.toContain("Secret party");
  expect(words).not.toContain(e.event.code);
  expect(await stored(page, "uwuhere.bugDraft")).toBeNull();
  noErrors(page);
});

test("Report a bug: not set up on the site offers email, and what's typed stays", async ({ page }) => {
  const db = await mockApi(page, { bugStatus: 503 });
  await seed(page);
  await openApp(page);
  await button(page, "Report a bug").click();
  await fill(page, page.getByRole("textbox", { name: /What went wrong/ }), "Nothing loads.");
  await button(page, "Send").click();
  await expect(said(page, "Bug reports can’t be sent from the app yet.")).toBeVisible();
  await expect(button(page, "Email it instead.")).toBeVisible();
  expect(db.bugReports.at(-1).platform).toBe("web");
  await expect(page.getByRole("textbox", { name: /What went wrong/ })).toHaveValue("Nothing loads.");
  noErrors(page);
});
