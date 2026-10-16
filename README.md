# uwuHere

Attendance in one tap, at [here.uwuapps.org](https://here.uwuapps.org).

A host makes an event and gets a code, a link and a QR code. People open it
and press one big button. It counts only if they are near the host: on the
same wifi as the host's open screen (a direct peer-to-peer link), or within a
set distance by location. The host sees the list live, can add or remove
people, pause check-ins, download a CSV, and end the event.

No accounts. The host page is kept in the browser that made the event, and an
optional password opens it on another device.

## Repository layout

```text
main-site/                      the app: static pages plus Vercel functions
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
   `migrations/` in order: `0001_uwuhere_tables.sql`, then
   `0002_uwuhere_purge.sql`. Both are safe to run twice.
2. **Vercel.** Root directory `main-site`. Set the five variables listed in
   `main-site/.env.example`. Vercel installs the one dependency (`bcryptjs`)
   from `main-site/package.json`.
3. **Domain.** Point `here.uwuapps.org` at the Vercel project.

### Migrations

| File | What it does | Needed? |
| --- | --- | --- |
| `0001_uwuhere_tables.sql` | `uwuhere_events` and `uwuhere_attendees`, RLS on with no policy | Yes. Nothing works without it. |
| `0002_uwuhere_purge.sql` | `uwuhere_purge_events()`, run daily by Vercel Cron | Yes, or old events are kept forever. |

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
