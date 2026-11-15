import { expect, test } from "@playwright/test";
import { hosted, makeEvent, mockApi, noErrors, openApp, seed, stored } from "./helpers.js";

// First-visit tours (lib/features/tour/tour.dart, docs/page-tour-spec.md). Every step's card stays
// on screen, and the thing it lights is scrolled into view (below the fold included) and kept lit
// as it moves, whatever the window's size.

async function cardBox(page) {
  const next = page.getByRole("button", { name: /^(Next|Done)$/ });
  await expect(next).toBeVisible();
  return next.boundingBox();
}

const inside = (box, viewport) => {
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.y).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(viewport.width);
  expect(box.y + box.height).toBeLessThanOrEqual(viewport.height);
};

/** Walks the tour, checking at each step that the card and what it's about are both on screen. */
async function walk(page, viewport, targets) {
  for (let i = 0; i < targets.length; i++) {
    await page.waitForTimeout(500);
    inside(await cardBox(page), viewport);
    if (targets[i]) {
      const t = await targets[i].first().boundingBox();
      // Some of it on screen: one taller than the window shows from its top.
      expect(t.y).toBeLessThan(viewport.height);
      expect(t.y + t.height).toBeGreaterThan(0);
    }
    const last = i === targets.length - 1;
    await page.getByRole("button", { name: last ? "Done" : "Next" }).click();
  }
  await expect(page.getByRole("button", { name: /^(Next|Done)$/ })).toHaveCount(0);
}

for (const viewport of [
  { width: 412, height: 892 },
  { width: 892, height: 412 },
]) {
  test(`home's welcome tour, every step on screen, ${viewport.width}×${viewport.height}`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await mockApi(page);
    await seed(page, {}, { tours: true });
    await openApp(page, "?android=1");
    await walk(page, viewport, [
      page.getByRole("textbox", { name: "Event code" }),
      page.getByRole("heading", { name: "Your events" }),
      page.getByRole("heading", { name: "Host an event" }),
      page.getByRole("switch", { name: "Same wifi" }),
      page.getByRole("button", { name: "Show me around" }),
    ]);
    expect(await stored(page, "uwuhere.tour.welcome")).toBe("done");
    noErrors(page);
  });
}

test("the host page's tour, the first time an event's open, and again from Show me around", async ({ page }) => {
  const viewport = { width: 412, height: 892 };
  const db = await mockApi(page);
  const e = makeEvent(db, { title: "Tour night" });
  await seed(page, { "uwuhere.hosted": hosted(e), "uwuhere.tour.welcome": "done" }, { tours: true });
  await openApp(page, `?android=1&page=host&id=${e.event.code}`, { ready: (p) => p.getByRole("heading", { name: "Tour night" }) });
  await walk(page, viewport, [
    page.getByRole("button", { name: /^Event code/ }),
    null,
    page.getByRole("button", { name: "Show the QR code big" }),
    null,
    page.getByRole("textbox", { name: "Name to add by hand" }),
    page.getByRole("button", { name: "End event" }),
    page.getByRole("button", { name: "Event settings" }),
  ]);
  expect(JSON.parse(await stored(page, "uwuhere.tour.pages"))).toContain("host");
  // Again, from the Edge Tray.
  await page.getByRole("button", { name: "Show me around" }).click();
  await page.getByRole("button", { name: "Host page" }).click();
  await expect(page.getByRole("button", { name: "Next" })).toBeVisible();
  noErrors(page);
});
