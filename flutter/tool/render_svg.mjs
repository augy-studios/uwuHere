// Renders an SVG to a PNG of a given size with Playwright's Chromium, for tool/make_icons.py.
//   node tool/render_svg.mjs <in.svg> <out.png> <size> [scale]
// scale (default 1) draws the SVG's #ui group that much smaller about the centre, for the
// launcher's adaptive foreground, and leaves the background out when given "fg".
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(new URL("../e2e/package.json", import.meta.url));
const { chromium } = require("@playwright/test");

const [, , input, output, size = "512", mode = ""] = process.argv;
let svg = readFileSync(input, "utf8");
const px = Number(size);
if (mode.startsWith("fg")) {
  // The adaptive icon's foreground: no backdrop, the figure at 80% about the centre.
  svg = svg.replace(/<rect width="1000" height="1000" fill="#ccffcc"\/>/, "");
  svg = svg.replace('<g id="ui" transform="translate(-37 -10)">', '<g transform="translate(500 500) scale(0.8) translate(-500 -500)"><g id="ui" transform="translate(-37 -10)">').replace(/<\/svg>\s*$/, "</g></svg>");
}
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: px, height: px } });
await page.setContent(`<html><body style="margin:0;background:transparent">${svg.replace("<svg ", `<svg width="${px}" height="${px}" `)}</body></html>`);
await page.locator("svg").screenshot({ path: output, omitBackground: true });
await browser.close();
