# The app in a browser, driven by Playwright

The real Flutter screens, built for the web from `main_e2e.dart`, with a stand-in for the Android
side (tapping phones, Bluetooth, the hotspot, notifications) and the site's API answered by the
tests from an in-memory store of events (`tests/helpers.js`), so they run offline and the same
every time. The website itself is served beside it by `site-serve.mjs`, for `tests/site.spec.js`
(Privacy, the tours, Report a bug) and `tests/site-sw.spec.js` (the service worker). This build is
for testing only and never ships.

```powershell
cd flutter\e2e
npm install
npx playwright install chromium
npm run build      # flutter build web, into flutter/build/web
npm test
```

The app is served on 47481 and the website on 47482.

Query parameters: `?android=1` draws as the Android app does (its Updates page, Material You by
default), `?wallpaper=1` pretends the phone has wallpaper colours, `?play=1` acts as the Google
Play build, `?nonfc=1` as a phone without NFC, `?desktop=1` draws the desktop's title bar and
events pane, `?welcome=1` the desktop's Make it yours window, `?native=fluent|tahoe|frosted` (with `?desktop=1`) which system's glass the desktop's second look is, `?notour=1` keeps tours from
starting, and `?page=host&id=CODE` or `?page=join&id=CODE` opens that page. What the app asked of its Android side is in `window.e2eCalls`, and
`window.e2eEmit(plugin, event, json)` says what Android would have said.

The tests find things as a screen reader would (`getByRole`, by name), so a change that makes a
button nameless, or names it twice, fails here.

`shots/capture.mjs` and `shots/compose.mjs` make the store's screenshots from the same build
(`GOOGLE-PLAY.md`, section 7): `node shots/capture.mjs` with `node serve.mjs` running, then
`node shots/compose.mjs`.
