import { expect, test } from "@playwright/test";
import { button, mockApi, noErrors, openApp, seed, stored } from "./helpers.js";

test("off Android, the site's look: light, dark and the brand colours, under the site's keys", async ({ page }) => {
  await mockApi(page);
  await seed(page);
  await openApp(page);
  await button(page, "Theme").click();
  await expect(page.getByRole("heading", { name: "Theme" })).toBeVisible();
  await button(page, "Dark").click();
  await expect.poll(() => stored(page, "uwuhere.mode")).toBe("dark");
  await button(page, "Not green 2").click();
  await expect.poll(() => stored(page, "uwuhere.colorTheme")).toBe("not-green-2");
  await button(page, "Time-based").click();
  await expect(page.getByText(/Following the clock\. Currently (light|dark)\./)).toBeVisible();
  noErrors(page);
});

test("on Android with wallpaper colours, Material You is the default, and the UwU Apps look a switch away", async ({ page }) => {
  await mockApi(page);
  await seed(page);
  await openApp(page, "?android=1&wallpaper=1");
  await button(page, "Theme").click();
  await expect(page.getByText("Colours and fonts from your device.")).toBeVisible();
  await expect(button(page, "Classic")).toHaveCount(0);
  await button(page, "UwU Apps").click();
  await expect.poll(() => stored(page, "app.look")).toBe("uwuapps");
  await expect(button(page, "Classic")).toBeVisible();
  await button(page, "Material You").click();
  await expect.poll(() => stored(page, "app.look")).toBe("material");
  noErrors(page);
});

test("on the desktop, the system's glass in Material You's place: Fluent 2, macOS Tahoe or Frosted Glass by the system", async ({ page }) => {
  for (const [style, name] of [["fluent", "Fluent 2"], ["tahoe", "macOS Tahoe"], ["frosted", "Frosted Glass"]]) {
    await page.setViewportSize({ width: 1280, height: 800 });
    await mockApi(page);
    await seed(page);
    await openApp(page, `?desktop=1&notour=1&native=${style}`, { ready: (p) => button(p, "Theme") });
    await button(page, "Theme").click();
    await expect(button(page, "Material You")).toHaveCount(0);
    await button(page, name).click();
    await expect.poll(() => stored(page, "app.look")).toBe("native");
    await expect(page.getByText(/in your accent colour\./)).toBeVisible();
    await expect(button(page, "Classic")).toHaveCount(0);
    await button(page, "UwU Apps").click();
    await expect.poll(() => stored(page, "app.look")).toBe("uwuapps");
    await expect(button(page, "Classic")).toBeVisible();
    noErrors(page);
    await page.evaluate(() => sessionStorage.clear());
  }
});

test("on the desktop, a Material You kept from before opens as the system's glass", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await mockApi(page);
  await seed(page, { "app.look": "material" });
  await openApp(page, "?desktop=1&notour=1&native=tahoe", { ready: (p) => button(p, "Theme") });
  await button(page, "Theme").click();
  await expect(page.getByText(/Liquid Glass/)).toBeVisible();
  noErrors(page);
});
