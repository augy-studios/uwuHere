import { expect, test } from "@playwright/test";

// The website's service worker (main-site/sw.js) as it runs once deployed: each page it keeps is
// served as that page, online and off, Privacy among them. On 127.0.0.1 it always asks the network
// first, so the site is opened at 127.0.0.2, which the browser trusts the same but the worker
// doesn't take for development (site-serve.mjs listens on both).
const SITE = "http://127.0.0.2:47482";

test("the pages the worker keeps open as themselves, online and offline", async ({ page, context }) => {
  // The site's Google Analytics, kept out of the test's visits.
  await context.route(/googletagmanager|google-analytics|doubleclick/, (r) => r.abort());
  await page.goto(`${SITE}/`);
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true);

  for (const offline of [false, true]) {
    await context.setOffline(offline);
    await page.goto(`${SITE}/privacy`);
    await expect(page).toHaveTitle("Privacy | uwuHere | UwU Apps");
    await expect(page.getByRole("heading", { level: 1, name: "Privacy" })).toBeVisible();
    await page.goto(`${SITE}/host?id=BCD234`);
    await expect(page.locator("#hostView")).toHaveCount(1);
    await page.goto(`${SITE}/`);
    await expect(page.locator("#createForm")).toHaveCount(1);
  }
  // Offline, an address it doesn't keep opens home rather than failing.
  await page.goto(`${SITE}/nowhere`);
  await expect(page.locator("#createForm")).toHaveCount(1);
  await context.setOffline(false);
});
