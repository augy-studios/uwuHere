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
