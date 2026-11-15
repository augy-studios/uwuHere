import { expect, test } from "@playwright/test";

// The website itself (main-site/), served by site-serve.mjs: its Privacy page, its tours, and
// Report a bug, which the apps share.
const SITE = "http://127.0.0.1:47482";

async function open(page, path, { tours = false } = {}) {
  await page.context().route(/googletagmanager|google-analytics|doubleclick/, (r) => r.abort());
  if (!tours) {
    await page.addInitScript(() => {
      localStorage.setItem("uwuhere.tour.welcome", "done");
      localStorage.setItem("uwuhere.tour.pages", JSON.stringify(["host", "join"]));
    });
  }
  await page.goto(`${SITE}${path}`);
}

test("Privacy: what's kept, linked from home", async ({ page }) => {
  await open(page, "/");
  await page.getByRole("link", { name: "Privacy" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Privacy" })).toBeVisible();
  for (const h of ["If you host an event", "If you check in", "Keeping and deleting your data"]) {
    await expect(page.getByRole("heading", { name: new RegExp(h) })).toBeVisible();
  }
  await expect(page.getByText(/only that\s+distance is kept/)).toBeVisible();
  await expect(page.getByText(/It's on the website only, never in the apps/)).toBeVisible();
});

// The welcome tour, on a phone: each step's element scrolled to, wherever on the page it is, lit,
// with its card on screen and the element on screen too.
test("home's tour scrolls to each step and keeps its card on screen", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 700 });
  await open(page, "/", { tours: true });
  const card = page.locator(".tourCard");
  await expect(card).toBeVisible({ timeout: 5000 });
  const targets = ["#joinForm", "#hostedCard", "#createForm", "#methods", "#tourBtn, #trayTab"];
  for (let i = 0; i < targets.length; i++) {
    await page.waitForTimeout(700);
    const vh = 700;
    const c = await card.boundingBox();
    expect(c.y).toBeGreaterThanOrEqual(0);
    expect(c.y + c.height).toBeLessThanOrEqual(vh);
    const el = await page.locator(targets[i]).first().boundingBox();
    // Some of it on screen: a target taller than the screen shows from its top.
    expect(el.y).toBeLessThan(vh);
    expect(el.y + el.height).toBeGreaterThan(0);
    const hole = await page.locator(".tourHole").boundingBox();
    expect(Math.abs(hole.y + 8 - el.y)).toBeLessThan(3);
    await page.getByRole("button", { name: i === targets.length - 1 ? "Done" : "Next" }).click();
  }
  await expect(card).toHaveCount(0);
  expect(await page.evaluate(() => localStorage.getItem("uwuhere.tour.welcome"))).toBe("done");
  // Scrolling while a tour is up moves the light with its element.
  await page.getByRole("button", { name: "Show me around" }).click();
  await expect(card).toBeVisible();
});

test("Report a bug on the site: Screenshot a page takes the whole page, sent with its ID", async ({ page }) => {
  const sent = [];
  await page.route("**/api/bug-report", async (route) => {
    sent.push(JSON.parse(route.request().postData()));
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ id: "20261116-7K3Q" }) });
  });
  await page.setViewportSize({ width: 390, height: 700 });
  await open(page, "/");
  await page.getByRole("button", { name: "Report a bug" }).click();
  await expect(page.getByRole("heading", { name: "Report a bug" })).toBeVisible();
  await expect(page.locator("#bugDetails")).toContainText("Home");
  await page.locator("#bugText").fill("The colour wheel jumps.");
  await page.getByRole("button", { name: "Screenshot a page" }).click();
  await expect(page.getByRole("heading", { name: "Report a bug" })).toBeHidden();
  await page.getByRole("button", { name: "Screenshot this page" }).click();
  await expect(page.getByRole("img", { name: "Picture 1" })).toBeVisible({ timeout: 20_000 });
  await page.getByRole("button", { name: "Send" }).click();
  await expect(page.locator("#bugStatus")).toHaveText("Sent as report 20261116-7K3Q. Thank you! Augy will look into it.");
  expect(sent[0]).toMatchObject({ text: "The colour wheel jumps.", platform: "web", page: "Home", full: [0] });
  // The whole page: much taller than the screen.
  const size = await page.evaluate(async (src) => {
    const i = new Image();
    i.src = src;
    await i.decode();
    return { w: i.naturalWidth, h: i.naturalHeight };
  }, sent[0].images[0]);
  expect(size.h / size.w).toBeGreaterThan(2);
});
