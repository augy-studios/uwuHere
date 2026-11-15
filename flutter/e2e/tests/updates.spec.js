import { expect, test } from "@playwright/test";
import { button, calls, mockApi, noErrors, openApp, seed } from "./helpers.js";

// As announcements/release-notes-<version>.md writes them.
const notes = [
  "Check-ins by NFC sticker, and a quicker host page.",
  "",
  "## Download",
  "",
  "| Device | File |",
  "|---|---|",
  "| Android 7.0 or newer | `uwuhere-2.1.0.apk` |",
  "",
  "## What's new",
  "",
  "### Android app",
  "- **NFC stickers**: a sticker on the door checks people in.",
  "- **Quicker host page**",
  "",
  "### Everywhere",
  "- Fewer taps to make an event",
].join("\n");

const release = {
  version: "2.1.0",
  apk: "https://github.com/augy-studios/uwuHere/releases/download/android-v2.1.0/uwuhere-2.1.0.apk",
  size: 41000000,
  sha256: "a".repeat(64),
  page: "https://github.com/augy-studios/uwuHere/releases/tag/android-v2.1.0",
  date: "2026-12-01T10:00:00Z",
  notes,
  history: [
    { version: "2.1.0", date: "2026-12-01T10:00:00Z", notes, page: "https://github.com/augy-studios/uwuHere/releases/tag/android-v2.1.0" },
    { version: "2.0.0", date: "2026-11-15T10:00:00Z", notes: "uwuHere's apps, rebuilt.", page: "https://github.com/augy-studios/uwuHere/releases/tag/android-v2.0.0" },
    { version: "1.0.0", date: "2026-10-18T10:00:00Z", notes: "The first uwuHere app.", page: "https://github.com/augy-studios/uwuHere/releases/tag/android-v1.0.0" },
  ],
};

test("a newer version shows a bar; the Updates page lists every version and joins New version alerts", async ({ page }) => {
  await mockApi(page, { release });
  await seed(page);
  await openApp(page, "?android=1&wallpaper=1");
  await expect(page.getByText("uwuHere 2.1.0 is out.").last()).toBeVisible();
  await button(page, "Update").click();

  await expect(page.getByText("Every version")).toBeVisible();
  // The newest, open by itself: its summary, then a card for each group, the Markdown read rather
  // than shown, and the download table left out.
  await expect(page.getByRole("button", { name: /^Version 2\.1\.0 v2\.1\.0 New .*3 changes/ })).toBeVisible();
  await expect(page.getByText("Check-ins by NFC sticker, and a quicker host page.")).toBeVisible();
  await expect(page.getByText(/^Android app\s+2\s+NFC stickers\s+A sticker on the door checks people in\.\s+Quicker host page$/)).toBeVisible();
  await expect(page.getByText(/\*\*|\| Device/)).toHaveCount(0);
  // This one, closed till it's pressed; the one before it under Earlier releases.
  const mine = page.getByRole("button", { name: /^Version 2\.0\.0 v2\.0\.0 Installed/ });
  await expect(mine).toBeVisible();
  await expect(page.getByText("Earlier releases")).toBeVisible();
  await mine.click();
  await expect(page.getByText("uwuHere's apps, rebuilt.")).toBeVisible();
  await expect(page.getByRole("button", { name: /Update \(41\.0 MB\)/ })).toBeVisible();

  await page.getByRole("switch", { name: /New versions of the app/ }).click();
  await expect.poll(async () => (await calls(page)).find((c) => c.method === "setReleases")?.options).toEqual({ on: true });
  // Downloading: the bar and the page say so with Material You's wavy line.
  await page.route("https://github.com/**", (r) => r.fulfill({ status: 200, body: Buffer.alloc(1000) }));
  noErrors(page);
});

test("up to date, the Edge Tray's Check for updates says so and still lists the versions", async ({ page }) => {
  await mockApi(page, { release: { ...release, version: "2.0.0", history: release.history.slice(1) } });
  await seed(page);
  await openApp(page, "?android=1");
  await expect(page.getByText("uwuHere 2.1.0 is out.")).toHaveCount(0);
  await button(page, "Check for updates").click();
  await expect(page.getByRole("group", { name: /^You’re up to date This is version 2\.0\.0\./ })).toBeVisible();
  await expect(page.getByText("uwuHere's apps, rebuilt.")).toBeVisible();
  noErrors(page);
});

test("the Play build shows no update bar of its own", async ({ page }) => {
  await mockApi(page, { release });
  await seed(page);
  await openApp(page, "?android=1&play=1");
  await page.waitForTimeout(1500);
  await expect(page.getByText("uwuHere 2.1.0 is out.")).toHaveCount(0);
});
