// Frames the pictures from capture.mjs as store screenshots, in the style SG Bus Timings' have:
// a backdrop of its own for each (a gradient and soft blobs of UwU Apps' brand colours), a headline in Jua, the app in a phone, tablet or window, and handwritten
// notes with arrows to what they're about. Writes them into docs/:
//
//   docs/phone-assets/01…08.png            1620 × 2880
//   docs/tablet-assets/7-inch/01…08.png    1620 × 2880
//   docs/tablet-assets/10-inch/01…08.png   2880 × 1620
//   docs/desktop-assets/01…08.png          2880 × 1620
//   docs/feature-graphic.png               1024 × 500
//
//     node shots/compose.mjs
import { chromium } from "@playwright/test";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const raw = (f) => pathToFileURL(join(here, "raw", `${f}.png`)).href;
const docs = join(here, "../../../docs");
const jua = pathToFileURL(join(here, "../../assets/fonts/Jua-Regular.ttf")).href;
const icon = pathToFileURL(join(here, "../../assets/images/icon-512.png")).href;

// What each picture says. `to` is where an arrow points, as a fraction of the screen it's on.
const portrait = [
  { file: "01-home", raw: "01-home", head: "Attendance<br>in one tap.", notes: [{ text: "Check in<br>with a code", side: "l", y: 0.38, to: [0.3, 0.16] }, { text: "Your events,<br>kept here", side: "r", y: 0.5, to: [0.75, 0.3] }] },
  { file: "02-host", raw: "02-host", head: "A code, a link<br>and a QR code.", notes: [{ text: "Scan to<br>check in", side: "l", y: 0.5, to: [0.32, 0.38] }, { text: "Ready for<br>check-ins", side: "r", y: 0.66, to: [0.8, 0.69] }] },
  { file: "03-list", raw: "03-list", head: "Watch it<br>fill up, live.", notes: [{ text: "Who, when<br>and how", side: "l", y: 0.72, to: [0.3, 0.86] }, { text: "Download<br>it as a CSV", side: "r", y: 0.5, to: [0.68, 0.56] }] },
  { file: "04-checkin", raw: "04-checkin", head: "One big button<br>for everyone.", notes: [{ text: "Only counts<br>near the host", side: "l", y: 0.62, to: [0.3, 0.55] }, { text: "Your name,<br>remembered", side: "r", y: 0.4, to: [0.78, 0.18] }] },
  { file: "05-qr", raw: "05-qr", head: "Turn your screen<br>to the room.", notes: [{ text: "As big as<br>it goes", side: "l", y: 0.6, to: [0.3, 0.7] }, { text: "At full<br>brightness", side: "r", y: 0.42, to: [0.85, 0.72] }] },
  { file: "06-theme", raw: "06-theme", head: "In your phone's<br>colours, or ours.", notes: [{ text: "Material You<br>or UwU Apps", side: "l", y: 0.62, to: [0.3, 0.86] }, { text: "Seven brand<br>colours", side: "r", y: 0.66, to: [0.72, 0.975] }] },
  { file: "07-updates", raw: "07-updates", head: "Always<br>up to date.", notes: [{ text: "What's new in<br>every version", side: "l", y: 0.72, to: [0.3, 0.9] }, { text: "A note when a<br>new one's out", side: "r", y: 0.5, to: [0.88, 0.7] }] },
  { file: "08-dark-tour", raw: "08-dark-tour", head: "Shown around<br>the first time.", notes: [{ text: "One step<br>at a time", side: "l", y: 0.66, to: [0.3, 0.8] }, { text: "Dark when<br>you like", side: "r", y: 0.4, to: [0.8, 0.3] }] },
];

const landscape = [
  { file: "01-home", raw: "01-home", head: "Attendance in one tap.", notes: [{ text: "Check in<br>with a code", side: "l", y: 0.4, to: [0.3, 0.2] }, { text: "Your events,<br>kept here", side: "r", y: 0.5, to: [0.7, 0.42] }] },
  { file: "02-host", raw: "02-host", head: "A code, a link and a QR code.", notes: [{ text: "Scan to<br>check in", side: "l", y: 0.55, to: [0.4, 0.5] }, { text: "Ready for<br>check-ins", side: "r", y: 0.5, to: [0.62, 0.86] }] },
  { file: "03-list", raw: "03-list", head: "Watch it fill up, live.", notes: [{ text: "Who, when<br>and how", side: "l", y: 0.62, to: [0.4, 0.7] }, { text: "Download<br>it as a CSV", side: "r", y: 0.42, to: [0.6, 0.4] }] },
  { file: "04-checkin", raw: "04-checkin", head: "One big button for everyone.", notes: [{ text: "Only counts<br>near the host", side: "l", y: 0.62, to: [0.42, 0.7] }, { text: "Your name,<br>remembered", side: "r", y: 0.4, to: [0.62, 0.32] }] },
  { file: "05-qr", raw: "05-qr", head: "Turn your screen to the room.", notes: [{ text: "As big as<br>it goes", side: "l", y: 0.6, to: [0.42, 0.55] }, { text: "At full<br>brightness", side: "r", y: 0.42, to: [0.58, 0.4] }] },
  { file: "06-theme", raw: "06-theme", head: "In your device's colours, or ours.", notes: [{ text: "Material You<br>or UwU Apps", side: "l", y: 0.5, to: [0.42, 0.42] }, { text: "Seven brand<br>colours", side: "r", y: 0.62, to: [0.56, 0.8] }] },
  { file: "07-updates", raw: "07-updates", head: "Always up to date.", notes: [{ text: "What's new in<br>every version", side: "l", y: 0.66, to: [0.35, 0.8] }, { text: "A note when a<br>new one's out", side: "r", y: 0.42, to: [0.9, 0.5] }] },
  { file: "08-dark-tour", raw: "08-dark-tour", head: "Shown around the first time.", notes: [{ text: "Dark when<br>you like", side: "l", y: 0.62, to: [0.3, 0.7] }, { text: "One step<br>at a time", side: "r", y: 0.36, to: [0.7, 0.3] }] },
];

const desktop = [
  { file: "01-home", raw: "01-home", head: "uwuHere, on your computer.", notes: [{ text: "Your events,<br>beside it", side: "l", y: 0.42, to: [0.1, 0.3] }, { text: "Make one in<br>a minute", side: "r", y: 0.5, to: [0.6, 0.3] }] },
  { file: "02-host", raw: "02-host", head: "Host from a laptop at the door.", notes: [{ text: "Scan to<br>check in", side: "l", y: 0.62, to: [0.4, 0.42] }, { text: "The list,<br>live", side: "r", y: 0.4, to: [0.8, 0.2] }] },
  { file: "03-command", raw: "03-command", head: "Find anything with Ctrl+K.", notes: [{ text: "Every event<br>and command", side: "l", y: 0.5, to: [0.36, 0.3] }, { text: "Or type a<br>code", side: "r", y: 0.32, to: [0.6, 0.01] }] },
  { file: "04-qr", raw: "04-qr", head: "Turn your screen to the room.", notes: [{ text: "As big as<br>it goes", side: "l", y: 0.6, to: [0.45, 0.5] }, { text: "The code,<br>to type in", side: "r", y: 0.5, to: [0.58, 0.8] }] },
  { file: "05-checkin", raw: "05-checkin", head: "One big button for everyone.", notes: [{ text: "Only counts<br>near the host", side: "l", y: 0.62, to: [0.62, 0.55] }, { text: "Your name,<br>remembered", side: "r", y: 0.4, to: [0.75, 0.25] }] },
  { file: "06-welcome", raw: "06-welcome", head: "Make it yours.", window: "Make uwuHere yours", notes: [{ text: "Starts when you<br>sign in", side: "r", y: 0.32, to: [0.92, 0.22] }, { text: "Or your computer's<br>accent colour", side: "r", y: 0.66, to: [0.96, 0.53] }] },
  { file: "07-dark", raw: "07-dark", head: "Light, dark, or by the clock.", notes: [{ text: "Dark when<br>you like", side: "l", y: 0.42, to: [0.4, 0.6] }, { text: "In any brand<br>colour", side: "r", y: 0.5, to: [0.5, 0.02] }] },
  { file: "08-settings", raw: "08-settings", head: "Change it as it runs.", notes: [{ text: "The ways<br>people check in", side: "l", y: 0.62, to: [0.62, 0.7] }, { text: "A password for<br>another device", side: "r", y: 0.3, to: [0.8, 0.3] }] },
];

// The backdrops, one per picture in turn: deep enough for the light writing on top, each with
// two bright blobs from UwU Apps' brand colours (mint, peach, lilac, sky, pink, lemon).
const palettes = [
  { a: "#1f6b3d", b: "#0d6f78", blobs: ["#5ee08f", "#ffd36e"] },
  { a: "#2b3f8f", b: "#0f6b8a", blobs: ["#8fb8ff", "#5ee0c8"] },
  { a: "#7a2858", b: "#4a2c8a", blobs: ["#ff8fb8", "#ffb36b"] },
  { a: "#0f5f5a", b: "#3a6a1f", blobs: ["#9be7c4", "#ffe680"] },
  { a: "#9a3f1f", b: "#7a1f4d", blobs: ["#ffb07a", "#ff7a9a"] },
  { a: "#34308f", b: "#7a2c7a", blobs: ["#b8a6ff", "#ff9ad5"] },
  { a: "#15684d", b: "#2f3c8f", blobs: ["#6fe8a8", "#9ec5ff"] },
  { a: "#1c2a44", b: "#3d2a6a", blobs: ["#5ab0ff", "#ccffcc"] },
];

/** A picture's backdrop: its gradient, and blobs placed for a w × h page. */
function backdrop(i, w, h) {
  const p = palettes[i % palettes.length];
  const blob = (colour, x, y, size, alpha) =>
    `<div class="blob" style="left:${x * w - size / 2}px;top:${y * h - size / 2}px;width:${size}px;height:${size}px;background:radial-gradient(circle, ${colour}${alpha} 0%, ${colour}00 68%)"></div>`;
  const big = Math.max(w, h);
  return {
    style: `background:linear-gradient(${w > h ? 120 : 160}deg, ${p.a} 0%, ${p.b} 100%)`,
    html:
      blob(p.blobs[0], 0.08, 0.86, big * 0.95, "cc") +
      blob(p.blobs[1], 0.95, 0.12, big * 0.7, "99") +
      blob(p.blobs[0], 0.9, 0.95, big * 0.5, "66") +
      blob(p.blobs[1], 0.12, 0.08, big * 0.35, "55"),
  };
}

const css = `
@font-face { font-family: Jua; src: url("${jua}"); }
* { box-sizing: border-box; margin: 0; }
body { width: var(--w); height: var(--h); overflow: hidden; background: #1f6b3d; font-family: Jua, sans-serif; position: relative; }
.blob { position: absolute; border-radius: 50%; pointer-events: none; }
.head { position: absolute; left: 0; right: 0; text-align: center; color: #fffbea; line-height: 1.08; text-shadow: 0 6px 30px rgba(0,0,0,.35); }
.screen { position: absolute; overflow: hidden; background: #fff; }
.screen img { width: 100%; height: 100%; object-fit: cover; object-position: top left; display: block; }
.frame { position: absolute; background: #121815; box-shadow: 0 40px 90px rgba(0,0,0,.35); }
.note { position: absolute; color: #fffbea; font-family: "Patrick Hand", "Segoe Print", cursive; text-align: center; line-height: 1.15; text-shadow: 0 3px 14px rgba(0,0,0,.45); }
svg { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
.status { position: absolute; left: 0; right: 0; top: 0; display: flex; justify-content: space-between; align-items: center; font-family: Roboto, "Segoe UI", sans-serif; color: #121815; }
.titlebar { position: absolute; left: 0; right: 0; top: 0; display: flex; align-items: center; color: #eef2ef; font-family: "Segoe UI", sans-serif; background: #121815; }
`;

function page({ w, h, body, bg = "" }) {
  return `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Patrick+Hand&display=swap" rel="stylesheet">
<style>:root{--w:${w}px;--h:${h}px}${css}</style></head><body style="${bg}">${body}
<svg id="arrows"></svg>
<script>
// Each note's arrow, from the note to the point on the screen it names, drawn once laid out.
document.fonts.ready.then(() => {
  const svg = document.getElementById('arrows');
  const screen = document.querySelector('.screen').getBoundingClientRect();
  for (const n of document.querySelectorAll('.note')) {
    const r = n.getBoundingClientRect();
    const [fx, fy] = JSON.parse(n.dataset.to);
    const tx = screen.left + fx * screen.width, ty = screen.top + fy * screen.height;
    const right = n.dataset.side === 'r';
    const sx = right ? r.left + r.width * 0.5 : r.left + r.width * 0.5;
    const sy = ty < r.top ? r.top - 14 : r.bottom + 14;
    const mx = (sx + tx) / 2 + (right ? 60 : -60), my = (sy + ty) / 2;
    const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    p.setAttribute('d', 'M' + sx + ',' + sy + ' Q' + mx + ',' + my + ' ' + tx + ',' + ty);
    p.setAttribute('fill', 'none'); p.setAttribute('stroke', '#fffbea'); p.setAttribute('stroke-width', ${w > 2000 ? 5 : 6}); p.setAttribute('stroke-linecap', 'round');
    svg.appendChild(p);
    const a = Math.atan2(ty - my, tx - mx), L = ${w > 2000 ? 26 : 34};
    for (const d of [0.8, -0.8]) {
      const h = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      h.setAttribute('d', 'M' + tx + ',' + ty + ' L' + (tx + Math.cos(a + Math.PI * d) * L) + ',' + (ty + Math.sin(a + Math.PI * d) * L));
      h.setAttribute('stroke', '#fffbea'); h.setAttribute('stroke-width', ${w > 2000 ? 5 : 6}); h.setAttribute('stroke-linecap', 'round');
      svg.appendChild(h);
    }
  }
  document.body.dataset.ready = '1';
});
</script></body></html>`;
}

const notesHtml = (notes, { w, h, fs, zone }) =>
  notes.map((n) => {
    const x = n.side === "l" ? zone.l : zone.r;
    return `<div class="note" data-side="${n.side}" data-to='${JSON.stringify(n.to)}' style="left:${x - zone.w / 2}px;width:${zone.w}px;top:${n.y * h}px;font-size:${fs}px">${n.text}</div>`;
  }).join("");

// A phone or a portrait tablet: headline above, the device in the middle, notes either side.
function portraitPage(s, raw, { tablet, i = 0 }) {
  const w = 1620, h = 2880;
  const back = backdrop(i, w, h);
  const sw = tablet ? 920 : 800;
  // A phone's status bar above the app, coloured from the picture's own top edge.
  const bar = tablet ? 0 : 60;
  const sh = Math.round(sw * (tablet ? 1000 / 600 : 892 / 412)) + bar;
  const bezel = tablet ? 44 : 30;
  const left = (w - sw) / 2, top = 620;
  const status = tablet ? "" : `<div class="status" style="height:${bar}px;padding:0 44px;font-size:30px;background:url('${raw}') top left / 100% 100000% no-repeat"><span>9:41</span><span>▴ ◼</span></div>`;
  const body = `
${back.html}
<div class="head" style="top:150px;font-size:150px">${s.head}</div>
<div class="frame" style="left:${left - bezel}px;top:${top - bezel}px;width:${sw + 2 * bezel}px;height:${sh + 2 * bezel}px;border-radius:${tablet ? 70 : 110}px"></div>
<div class="screen" style="left:${left}px;top:${top}px;width:${sw}px;height:${sh}px;border-radius:${tablet ? 30 : 80}px"><img src="${raw}" style="position:absolute;top:${bar}px;height:${sh - bar}px">${status}</div>
${notesHtml(s.notes, { w, h, fs: tablet ? 52 : 60, zone: { l: left / 2, r: w - left / 2, w: left - 36 } })}`;
  return { w, h, html: page({ w, h, body, bg: back.style }) };
}

// A landscape tablet or the desktop: headline above, the device or window, notes either side.
function landscapePage(s, raw, { desktop: isDesktop, i = 0 }) {
  const w = 2880, h = 1620;
  const back = backdrop(i, w, h);
  const welcome = !!s.window;
  const ratio = welcome ? 660 / 940 : isDesktop ? 900 / 1440 : 800 / 1280;
  const sw = welcome ? 1620 : 2000, sh = Math.round(sw * ratio);
  const left = (w - sw) / 2, top = welcome ? 330 : 300;
  let frame;
  if (isDesktop) {
    // A window: its own title bar is the app's (or, for Make it yours, the system's simple one).
    frame = `<div class="frame" style="left:${left - 3}px;top:${top - 3}px;width:${sw + 6}px;height:${sh + 6}px;border-radius:18px;background:#0b0f0c"></div>`;
  } else {
    frame = `<div class="frame" style="left:${left - 40}px;top:${top - 40}px;width:${sw + 80}px;height:${sh + 80}px;border-radius:60px"></div>`;
  }
  const body = `
${back.html}
<div class="head" style="top:70px;font-size:130px">${s.head}</div>
${frame}
<div class="screen" style="left:${left}px;top:${top}px;width:${sw}px;height:${sh}px;border-radius:${isDesktop ? 14 : 24}px"><img src="${raw}"></div>
${notesHtml(s.notes, { w, h, fs: 54, zone: { l: left / 2, r: w - left / 2, w: left - 40 } })}`;
  return { w, h, html: page({ w, h, body, bg: back.style }) };
}

function featureGraphic() {
  const w = 1024, h = 500;
  const back = backdrop(0, w, h);
  const body = `
${back.html}
<img src="${icon}" style="position:absolute;left:70px;top:120px;width:150px;height:150px;border-radius:34px;box-shadow:0 18px 40px rgba(0,0,0,.3)">
<div style="position:absolute;left:250px;top:128px;color:#fffbea;font-size:72px;text-shadow:0 4px 18px rgba(0,0,0,.35)">uwuHere</div>
<div style="position:absolute;left:256px;top:232px;color:#eaffea;font-size:38px">Attendance in one tap</div>
<div style="position:absolute;left:72px;top:330px;width:440px;color:#fffbea;font-family:'Patrick Hand',cursive;font-size:34px;line-height:1.15;text-shadow:0 3px 12px rgba(0,0,0,.4)">People check in when they're near you. No accounts, no app needed</div>
<div class="frame" style="left:676px;top:58px;width:300px;height:620px;border-radius:44px;transform:rotate(8deg)"></div>
<div class="screen" style="left:690px;top:72px;width:272px;height:590px;border-radius:34px;transform:rotate(8deg)"><img src="${raw("phone-02-host")}"></div>`;
  return { w, h, html: page({ w, h, body, bg: back.style }).replace('<svg id="arrows"></svg>', "").replace("<div class=\"screen\"", "<div class=\"screen\"") };
}

async function render(browser, { w, h, html }, out) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  // From a file, so the page may read the pictures and fonts beside it.
  const tmp = join(here, ".page.html");
  writeFileSync(tmp, html);
  await p.goto(pathToFileURL(tmp).href, { waitUntil: "networkidle" });
  await p.waitForFunction(() => document.body.dataset.ready === "1" || !document.querySelector(".note"), null, { timeout: 15000 }).catch(() => {});
  await p.waitForTimeout(300);
  mkdirSync(dirname(out), { recursive: true });
  await p.screenshot({ path: out, type: "png" });
  await ctx.close();
  console.log(out.replace(docs, "docs"));
}

const browser = await chromium.launch();
try {
  for (const [i, s] of portrait.entries()) {
    await render(browser, portraitPage(s, raw(`phone-${s.raw}`), { tablet: false, i }), join(docs, "phone-assets", `${s.file}.png`));
    await render(browser, portraitPage(s, raw(`tablet7-${s.raw}`), { tablet: true, i }), join(docs, "tablet-assets/7-inch", `${s.file}.png`));
    const l = landscape[i];
    await render(browser, landscapePage(l, raw(`tablet10-${l.raw}`), { desktop: false, i }), join(docs, "tablet-assets/10-inch", `${l.file}.png`));
  }
  for (const [i, s] of desktop.entries()) await render(browser, landscapePage(s, raw(`desktop-${s.raw}`), { desktop: true, i }), join(docs, "desktop-assets", `${s.file}.png`));
  await render(browser, featureGraphic(), join(docs, "feature-graphic.png"));
} finally {
  await browser.close();
}
