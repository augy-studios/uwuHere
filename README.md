# uwuHere

Attendance in one tap, at [here.uwuapps.org](https://here.uwuapps.org).

A host makes an event and gets a code, a link and a QR code. People open it
and press one big button. It counts only if they are near the host: on the
same wifi as the host's open screen (a direct peer-to-peer link), or within a
set distance by location. The host sees the list live, can add or remove
people, pause check-ins, download a CSV, and end the event.

No accounts. The host page is kept in the browser that made the event, and an
optional password opens it on another device.

There are apps too, built with Flutter from one project: for Android (Material You by default,
tapping phones, Bluetooth check-in from app to app, your phone as the wifi when the venue has
none, home screen widgets, notifications, and an Updates page) and for Windows, macOS and Linux
(your events beside the page, a command bar, a widget and the tray). Downloads are on the
[latest release](https://github.com/augy-studios/uwuHere/releases/latest), and
[Privacy](https://here.uwuapps.org/privacy) says what's kept and when it's deleted. The website
and PWA work as before, and attendees never need an app.

## Repository layout

```text
main-site/                      the website: static pages plus Vercel functions
flutter/                        the Android, Windows, macOS and Linux apps (flutter/README.md)
release/                        the APKs and the App Bundle, one folder per version, and how to publish
announcements/                  release notes for GitHub and Google Play, and Telegram announcements
migrations/                     SQL to run once in the Supabase SQL editor
docs/                           the specs the site and the apps follow, the icon, and the store's screenshots
scripts/                        bug-report-test.mjs, Report a bug's API tested without Telegram
.github/workflows/              builds the desktop installers onto the GitHub release
GOOGLE-PLAY.md                  putting the Android app on Google Play
BUG-REPORT-SETUP.md             the Telegram bot that Report a bug sends through
CODE_OF_CONDUCT.md
LICENSE                         MIT
```

`main-site/README.md` covers the app itself: what each file does, how
check-in works, where data lives, and what to do before a deploy.

## Setting it up

1. **Supabase.** In the shared uwuapps project's SQL editor, run the files in
   `migrations/` in order, `0001` to `0005`. All are safe to run twice.
2. **Vercel.** Root directory `main-site`. Set the five variables listed in
   `main-site/.env.example`. Vercel installs the one dependency (`bcryptjs`)
   from `main-site/package.json`.
3. **Domain.** Point `here.uwuapps.org` at the Vercel project.
4. **Apps (optional).** Build the Android app with one command from the
   project root, `powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1`
   (add `-Aab` for Google Play), which puts the signed file in
   `release/<version>/`. GitHub Actions builds the desktop apps on each release.
   `flutter/README.md` covers building, `release/README.md` publishing,
   `GOOGLE-PLAY.md` the store, `flutter/FIREBASE-SETUP.md` notifications and
   `BUG-REPORT-SETUP.md` Report a bug.

### Migrations

| File | What it does | Needed? |
| --- | --- | --- |
| `0001_uwuhere_tables.sql` | `uwuhere_events` and `uwuhere_attendees`, RLS on with no policy | Yes. Nothing works without it. |
| `0002_uwuhere_purge.sql` | `uwuhere_purge_events()`, run daily by Vercel Cron | Yes, or old events are kept forever. |
| `0003_uwuhere_tap.sql` | Tapping phones: `allow_tap`, the `tap` method, each tap's nonce | Yes, **before** deploying the site that reads it, or every event fails to load. |
| `0004_uwuhere_offline.sql` | The `tap_late` and `hotspot` methods, for check-ins with no internet | Yes, before deploying the site that sends them, or they're refused. |
| `0005_uwuhere_bluetooth.sql` | `allow_bluetooth`, and the `mesh` method for Bluetooth app to app. Also allows a `bluetooth` method, left over from a Chrome Web Bluetooth design that wasn't built; nothing writes it | Yes, **before** deploying the site that reads it, or every event fails to load. |

Every table is prefixed `uwuhere_`. Only the serverless functions touch them,
with the service role key; RLS with no policy means the anon key reaches
nothing. **Migrations are never edited once written.** A change is a new,
numbered file.

One stale comment to know about: `0001` describes `password_hash` as scrypt.
Passwords moved to bcrypt after that file was written, and since migrations
are not edited the comment stays. The column is plain text and holds the
bcrypt string; see `main-site/api/_lib/auth.js`.

## The specs

The specs in `docs/` are shared with the other UwU Apps projects, and they are
the source of truth for what they cover. When one of them changes, the site and
the apps follow it.

- **`uwuapps-theme.md`**: seven brand colours and light, dark or time-based
  mode. `css/theme.css` and `js/theme.js` follow it, with only the storage key
  changed.
- **`update-bar-spec.md`**: a new service worker never activates by itself;
  the bar asks first.
- **`edge-tray-spec.md`**: the collapsible column of buttons at the top right.
- **`STUN-p2p-spec.md`**: the same-wifi check-in. uwuHere uses it STUN only,
  on purpose: a TURN relay would let a phone anywhere reach the host, and the
  check would prove nothing.
- **`page-tour-spec.md`**: the first-visit tours, on the site and in the apps.
- **`flutter-android-app-spec.md`**, **`flutter-desktop-app-spec.md`**,
  **`desktop-features-spec.md`**: what the apps are and how they're built.

## Running it locally

```bash
cd main-site
npm install
npx vercel dev
```

`vercel dev` serves the pages and the functions together, reading
`.env.local`. Use `localhost` rather than a LAN address: the service worker,
geolocation and the hashing the attendee page does all need a secure context.

## Licence

MIT, see `LICENSE`.
