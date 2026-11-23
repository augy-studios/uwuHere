// Takes one screenshot of the app served on 47391 and prints any errors the page logged.
// Usage: node peek.mjs <output.png> [query] [width] [height]
import { chromium } from "@playwright/test";
const [, , outputPath, query = "", widthText = "412", heightText = "892"] = process.argv;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: Number(widthText), height: Number(heightText) }, deviceScaleFactor: 1 });
const errors = [];
page.on("pageerror", (error) => {
  errors.push(String(error));
});
page.on("console", (message) => {
  if (message.type() === "error") {
    errors.push(message.text());
  }
});
await page.goto("http://127.0.0.1:47391/" + query);
await page.waitForTimeout(4500);
await page.screenshot({ path: outputPath });
const errorReport = errors.join("\n");
if (errorReport) {
  console.log(errorReport);
} else {
  console.log("no errors");
}
await browser.close();
