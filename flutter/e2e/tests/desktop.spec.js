import { expect, test } from "@playwright/test";
import { button, hosted, makeEvent, mockApi, noErrors, openApp, reveal, seed } from "./helpers.js";

// The desktop apps' screens (lib/desktop/), drawn in the browser with ?desktop=1: the title bar,
// its command bar and buttons, the events pane beside the open page, and pointing hands.
test.use({ viewport: { width: 1440, height: 900 }, isMobile: false, hasTouch: false });

const homeReady = (p) => p.getByRole("heading", { name: "Host an event" });

test("the events pane and the open page side by side; the command bar finds events and codes", async ({ page }) => {
  const db = await mockApi(page);
  const a = makeEvent(db, { title: "Morning lecture" });
  const b = makeEvent(db, { title: "Evening lab" });
  await seed(page, { "uwuhere.hosted": hosted(a, b) });
  await openApp(page, "?desktop=1", { ready: homeReady });
  // Master and detail: the pane keeps your events and the code box, so home leaves them out.
  await expect(page.getByRole("heading", { name: "Your events" })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Checking in?" })).toHaveCount(1);

  // Picking an event opens its host page beside the pane.
  await page.getByRole("button", { name: /^Evening lab/ }).click();
  await expect(page.getByRole("heading", { name: "Evening lab" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Your events" })).toBeVisible();
  // Its own buttons in the title bar.
  await expect(button(page, "Event settings")).toBeVisible();
  await expect(button(page, "Show the QR code")).toBeVisible();

  // The command bar: an event by its name.
  await page.keyboard.press("Control+k");
  await page.waitForTimeout(500);
  await page.getByRole("textbox", { name: /^Search/ }).click();
  await page.waitForTimeout(400);
  await page.keyboard.type("morning", { delay: 30 });
  await page.keyboard.press("Enter");
  await expect(page.getByRole("heading", { name: "Morning lecture" })).toBeVisible();
  // A code: its check-in page.
  await page.keyboard.press("Control+k");
  await page.waitForTimeout(500);
  await page.getByRole("textbox", { name: /^Search/ }).click();
  await page.waitForTimeout(400);
  await page.keyboard.type(b.event.code, { delay: 30 });
  await page.keyboard.press("Enter");
  await expect(button(page, "I'm here")).toBeVisible();
  // Back, through the title bar's history.
  await button(page, "Back").click();
  await expect(page.getByRole("heading", { name: "Morning lecture" })).toBeVisible();
  noErrors(page);
});

// What the person asked for on the desktop: the pointing hand over buttons and everything else
// that can be pressed. Flutter on the web shows it by setting the cursor on its view.
test("a pointing hand over everything pressable", async ({ page }) => {
  const db = await mockApi(page);
  const a = makeEvent(db, { title: "Hands" });
  await seed(page, { "uwuhere.hosted": hosted(a) });
  await openApp(page, "?desktop=1", { ready: homeReady });
  const cursorAt = async (locator) => {
    const box = await (await reveal(page, locator, { x: 1000 })).boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.waitForTimeout(200);
    // Whatever's under the pointer, and everything it sits in (into Flutter's shadow roots).
    return page.evaluate(([x, y]) => {
      const out = [];
      let e = document.elementFromPoint(x, y);
      while (e) {
        out.push(getComputedStyle(e).cursor);
        e = e.parentElement || e.getRootNode().host;
      }
      return out.join("|");
    }, [box.x + box.width / 2, box.y + box.height / 2]);
  };
  for (const l of [
    button(page, "Create event"),
    page.getByRole("switch", { name: "Location" }),
    page.getByRole("button", { name: /^Hands/ }),
    button(page, "Theme"),
    button(page, "Copy link"),
  ]) {
    expect(await cursorAt(l)).toContain("pointer");
  }
  // And the arrow over what isn't.
  expect(await cursorAt(page.getByRole("heading", { name: "Host an event" }))).not.toContain("pointer");
  noErrors(page);
});
