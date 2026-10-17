# uwuHere

Attendance in one tap, at [here.uwuapps.org](https://here.uwuapps.org).

A host makes an event and gets a code, a link and a QR code. People open it
and press one big button. It counts only if they are near the host: on the
same wifi as the host's open screen (a direct peer-to-peer link), or within a
set distance by location. The host sees the list live, can add or remove
people, pause check-ins, download a CSV, and end the event.

No accounts. The host page is kept in the browser that made the event, and an
optional password opens it on another device.

It also comes as an Android app: the same site in a Capacitor WebView, which
adds what a web page can't do there (the host's screen kept on, the QR code at
full brightness, the CSV saved to Downloads, check-in notifications) and
updates itself from GitHub Releases. The website and PWA work as before.

## Repository layout

```text
main-site/                      the app: static pages plus Vercel functions
android/                        the Android app (Capacitor), see android/README.md
release/                        built and signed APKs, one folder per version
migrations/                     SQL to run once in the Supabase SQL editor
uwuapps-theme.md                theme spec, shared across UwU Apps
uwuapps-retrofit-time-mode.md   how time-based mode is added to the theme
update-bar-spec.md              the "new version is ready" bar
edge-tray-spec.md               the floating action tray, top right
STUN-p2p-spec.md                peer-to-peer pairing over STUN only
CODE_OF_CONDUCT.md
LICENSE                         MIT
```

`main-site/README.md` covers the app itself: what each file does, how
check-in works, where data lives, and what to do before a deploy.

## Setting it up

1. **Supabase.** In the shared uwuapps project's SQL editor, run the files in
   `migrations/` in order, `0001` to `0004`. All are safe to run twice.
2. **Vercel.** Root directory `main-site`. Set the five variables listed in
   `main-site/.env.example`. Vercel installs the one dependency (`bcryptjs`)
   from `main-site/package.json`.
3. **Domain.** Point `here.uwuapps.org` at the Vercel project.
4. **Android app (optional).** Build it with one command from the project
   root, `powershell -ExecutionPolicy Bypass -File android\build-apk.ps1`, which
   puts the signed APK in `release/<version>/`. `android/README.md` covers the
   first build's signing key, `release/README.md` publishing it, and
   `android/FIREBASE-SETUP.md` its notifications.

### Migrations

| File | What it does | Needed? |
| --- | --- | --- |
| `0001_uwuhere_tables.sql` | `uwuhere_events` and `uwuhere_attendees`, RLS on with no policy | Yes. Nothing works without it. |
| `0002_uwuhere_purge.sql` | `uwuhere_purge_events()`, run daily by Vercel Cron | Yes, or old events are kept forever. |
| `0003_uwuhere_tap.sql` | Tapping phones: `allow_tap`, the `tap` method, each tap's nonce | Yes, **before** deploying the site that reads it, or every event fails to load. |
| `0004_uwuhere_offline.sql` | The `tap_late` and `hotspot` methods, for check-ins with no internet | Yes, before deploying the site that sends them, or they're refused. |

Every table is prefixed `uwuhere_`. Only the serverless functions touch them,
with the service role key; RLS with no policy means the anon key reaches
nothing. **Migrations are never edited once written.** A change is a new,
numbered file.

One stale comment to know about: `0001` describes `password_hash` as scrypt.
Passwords moved to bcrypt after that file was written, and since migrations
are not edited the comment stays. The column is plain text and holds the
bcrypt string; see `main-site/api/_lib/auth.js`.

## The specs

The `.md` files at the root are portable specs shared with other UwU Apps
projects, and they are the source of truth for what they cover. When one of
them changes, the app follows it.

- **`uwuapps-theme.md`**: seven brand colours and light, dark or time-based
  mode. `css/theme.css` and `js/theme.js` follow it, with only the storage key
  changed.
- **`update-bar-spec.md`**: a new service worker never activates by itself;
  the bar asks first.
- **`edge-tray-spec.md`**: the collapsible column of buttons at the top right.
- **`STUN-p2p-spec.md`**: the same-wifi check-in. uwuHere uses it STUN only,
  on purpose: a TURN relay would let a phone anywhere reach the host, and the
  check would prove nothing.

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
