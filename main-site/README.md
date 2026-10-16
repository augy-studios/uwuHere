# uwuHere

The app: static pages and a handful of Vercel functions, deployed to
[here.uwuapps.org](https://here.uwuapps.org). No build step.

For the repository as a whole, setup, and the migrations, see the
[root README](../README.md).

## Pages

| Address | File | Who |
| --- | --- | --- |
| `/` | `index.html` | Anyone: join by code, make an event, see the events this browser hosts |
| `/host?id=CODE` | `host.html` | The host: code, QR, live list, settings, End event |
| `/join?id=CODE` | `join.html` | Attendees: the big button, and "I'm leaving early" under it |

`cleanUrls` in `vercel.json` serves each page without its `.html`.

## How check-in works

The host picks one or both ways to prove someone is here.

**Same wifi (P2P).** The host page registers with the public PeerJS broker as
`uwuhere-CODE` and waits. An attendee's tap opens a direct WebRTC data channel
to it, sends their name, and the host page saves the check-in. Without a TURN
relay a direct channel almost always means the same network or a hotspot.
The host page has to stay open, and asks for a screen wake lock so it does.

**Location.** The attendee's browser reads its location once and sends it to
`/api/checkin`, which works out the distance from the spot the host set and
accepts it within the radius plus up to 100 m of the phone's own stated
accuracy. Only the distance is stored, never the coordinates.

With both on, the attendee page tries same wifi first, since it needs no
permission prompt, and falls back to location.

**Once per browser.** A successful check-in is remembered in the attendee's
browser and the button stays done. The server also keeps one row per device
per event (a SHA-256 of a random id the browser makes), so a second tap from
the same browser is answered with the first check-in. A failed attempt does
not use the tap. Clearing site data does make a new device id, so someone
determined can check in twice under two names: the host can remove the extra.

**Leaving early** unlocks after check-in, works once, and needs no proximity
check, since saying you left is never in your favour. It takes the raw device
id, which only the attendee's browser has; the host only ever sees the hash.

## The host

- **Host key.** Making an event returns a key, kept in this browser's
  storage. It is an HMAC of the event id, so nothing has to be stored for it.
- **Password (optional).** Opens the host page on another device. Checked
  after NIST SP 800-63B-4 for a single-factor password: at least 14
  characters (one under NIST's 15), no rules about symbols or digits, and refused if it is a repeat,
  a keyboard or alphabet run, contains the event's name or code, or appears in
  the Have I Been Pwned breach corpus (k-anonymity: only five hex characters of
  a SHA-1 leave the server). Stored as
  `bcrypt(base64(HMAC-SHA384(password, pepper)))` at cost 12, the OWASP
  pattern that keeps bcrypt's 72 byte limit from cutting long passwords short.
- **End event** closes the event for everyone and marks it for deletion. The
  list can still be downloaded from the host page for 7 days, then the daily
  purge deletes it. Events nobody ends are deleted after 30 days.
- **Offline.** The host page opens from cache with its last copy of the list,
  and the CSV still downloads from it. Same-wifi check-ins that arrive while
  the API cannot be reached go into an outbox in the browser, the attendee is
  told they are in, and the outbox is sent when it can be. People added by
  hand offline go the same way. New same-wifi check-ins themselves need the
  internet, because the PeerJS broker introduces the two devices. Pausing,
  settings and ending need a connection.
- **CSV.** Names come from attendees, so any cell starting with `= + - @` is
  prefixed with an apostrophe to keep spreadsheets from running it.

## Layout

```text
index.html, host.html, join.html   the three pages
css/theme.css        the uwuapps theme, per uwuapps-theme.md
css/app.css          layout, the big button, the tray, the update bar
js/theme.js          7 brand colours, light/dark/time-based mode
js/shell.js          what every page shares: theme modal, tray, update bar
js/tray.js           the edge tray, per edge-tray-spec.md
js/sw-update.js      the update bar, per update-bar-spec.md
js/p2p.js            PeerJS host and attendee, STUN only, per STUN-p2p-spec.md
js/home.js           the home page
js/host.js           the host page
js/join.js           the attendee page
js/api.js            fetch wrapper for /api, offline as an ordinary answer
js/store.js          everything kept in localStorage, under "uwuhere."
js/password.js       the live password checklist, mirrors api/_lib/password.js
js/colour-picker.js  the button colour's wheel, brightness and hex code box
js/geo.js            one Geolocation reading, with sentences for failures
js/qr.js             QR encoder, so the code works offline (from uwuPromptr)
js/icons.js, ui.js   inline SVG icons; modals, toasts, small helpers
js/app-bridge.js     the channel to the Android app (../android), when open in it
js/app-update.js     the app's own update check, and the tray's "Check for updates"
js/app-notify.js     the app's notifications bell, and each event's check-in alerts
sw.js                service worker: caches the shell, waits to update
check-precache.js    checks sw.js's list against what is on disk
api/                 Vercel functions, see below
.env.example         the Vercel environment variables
```

### API

| Endpoint | Does |
| --- | --- |
| `POST /api/events` | Make an event. Answers the code and host key. |
| `GET /api/event?code=` | What the attendee page needs. With `X-Uwuhere-Device`, also whether this browser is checked in. |
| `POST /api/checkin` | Check in by location. |
| `POST /api/leave` | I'm leaving early. |
| `POST /api/host` | Everything the host does, by `action`: get, record, add, remove, pause, resume, update, password, end. |
| `POST /api/unlock` | Password to host key, for another device. |
| `GET /api/cron/purge` | The daily purge, run by Vercel Cron with `CRON_SECRET`. |
| `GET /api/app-release` | The Android app's newest release on GitHub, for its updater. Cached at the edge for 10 minutes. |
| `POST /api/push/release` | GitHub's webhook for a published release: tells the app's phones a new version is out. |

Every answer is `{ ok: true, data }` or `{ ok: false, error, reason }`, sent
`Cache-Control: no-store`. `error` is a sentence for a person; `reason` is a
fixed slug the pages branch on. Shared code is in `api/_lib/`. The two
Android app endpoints answer in their own shapes, as GitHub and the app's
updater expect (`api/app-release.js`, `api/push/release.js`).

`/api/checkin` and `/api/leave` also notify the host's phones in the Android
app, if they turned check-in notifications on (`api/_lib/alerts.js`). It is
skipped without `FIREBASE_SERVICE_ACCOUNT`, and never fails the check-in.

## Environment

Five variables run the site, all server side, documented in `.env.example`:
`SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `UWUHERE_HOST_SECRET`,
`UWUHERE_PASSWORD_PEPPER`, `CRON_SECRET`. Generate the three secrets with
`openssl rand -hex 32`, and never change the host secret or the pepper once
events exist. Changing the host secret also renames every event's check-in
notification topic, so hosts reopen their pages to get them again.

Three more, all optional, are for the Android app (`../android/FIREBASE-SETUP.md`):
`FIREBASE_SERVICE_ACCOUNT`, `GITHUB_WEBHOOK_SECRET`, `GITHUB_TOKEN`.

One public ID is written into each page's `<head>`, as in the template:
`G-FMCYFTFPEL` (Google Analytics). There are no ads.

## Theme

Seven brand colours and three mode settings, per `uwuapps-theme.md`. The
daylight hours for time-based mode (09:00 to 18:00) appear in `js/theme.js`
and in the pre-paint script in each page's `<head>`. **Change them together.**
The big button's colour is the host's choice, not the theme: its text is
worked out as black or white, whichever contrasts more.

## Deploying

**Bump `VERSION` in `sw.js` whenever anything the worker serves changes.** The
browser compares the worker byte for byte, so a version left alone is an
update bar nobody sees, and returning visitors keep the old build.

Before a deploy:

```bash
node check-precache.js
```

It fails on a precached path with no file, a shipped file nobody precaches
(which works online and vanishes offline), a duplicate, or a `skipWaiting()` /
`clients.claim()` outside the worker's message handler. A file that should not
be cached goes in its `DELIBERATELY_ABSENT` list with the reason.

### Checking the update bar by hand

1. Open the site, let the worker install, confirm no bar.
2. Bump `VERSION` and deploy.
3. Reload once. The bar appears.
4. **Not now** hides it for this page view only.
5. **Reload** reloads once, onto the new version, and the bar is gone.
6. Repeat with a tab left open across the deploy.

On `localhost` the worker goes to the network first, so edits show without a
bump, and the bar can only be seen by bumping `VERSION`.

In the Android app the same bar also announces a new version of the app
itself (`js/app-update.js`); the site's own new version takes precedence, and
the app's shows after the reload. `../android/README.md` has the app's checks.

### Checking check-in by hand

- Two devices on one wifi: join by code, link and QR; the host sees the name
  within a second.
- A phone on mobile data against a host on wifi: "Could not reach the host's
  screen" within 15 seconds, then location if it is on. Never a hang.
- `chrome://webrtc-internals` during a check-in shows STUN servers only, and a
  `host` or `srflx` pair, never `relay`.
- Tap twice, reload, tap again: one row, button stays done.
- `/api/host` blocked in devtools (request blocking) while a same-wifi
  check-in arrives: "Not sent yet" on the host, sent once unblocked.
- Host fully offline: the page and its last list still open; the same-wifi
  status says it needs a connection, since the broker introduces the devices.
