# Checking in without internet

How uwuHere takes check-ins at a venue with no internet, given how it's used:
**only the host has the Android app**, and attendees, most of them, check in
from a browser, iPhones included.

## What works, and what each side needs

| Method | Host's phone with no internet | Attendee's phone with no internet |
|---|---|---|
| **Tapping phones** | Works. The host's phone signs each tap's token itself (`TapService.java`) | Works for anyone who has opened uwuHere before: the tap is kept and sent later (below) |
| **The host's hotspot** | Works. That's what it's for | Works, for everyone (below) |
| **Bluetooth, app to app** | Works | Works, for attendees with the app (below) |
| **Location** | Works. The server checks the distance | Fails |
| **Same wifi** | Fails. The PeerJS broker introduces the two devices | Fails |
| **Added by hand** | Works. Kept in the host page's outbox and sent later | Not involved |

## The host's hotspot

On the host page in the app: **No internet for attendees? → Start**. The phone
becomes a wifi hotspot of its own (Android's local-only hotspot, which shares no
internet) and serves a check-in page on it (`Hotspot.java`, `LocalServer.java`,
`res/raw/hotspot_page.html`). The host page shows two QR codes, one to join the
wifi and one to open the page, which iPhone and Android cameras both read.

- **Works for every attendee**: no app, nothing cached, iPhones included.
- **Proof of presence**: being on the hotspot, which reaches across a room or
  so. The wifi password changes every time the hotspot starts.
- **Where check-ins go**: to the host page, the same way as a same-wifi one: to
  uwuHere if this phone has a connection, or into the outbox until it does. The
  list shows them as "Host's hotspot".
- **The host page has to stay open.** It's what records each check-in, and the
  attendee waits for its answer. The screen is kept on while the hotspot is up.
  Leaving the page, ending the event, or closing the app stops the hotspot.
- **Asks once**: "Nearby devices" on Android 13 and later; location on Android
  8 to 12, which also needs location switched on. Not available before Android 8.
- **The page is plain `http`** on the phone's own address, such as
  `http://192.168.43.1:8080/`, because nothing on a hotspot without internet can
  get a certificate. It needs neither a service worker nor location, so that's
  fine. It keeps its own device id, so someone who checks in through it and
  again some other way shows twice; the host can remove one.
- **Attendees with mobile data** may find their phone reaching for that instead
  of the hotspot, as Android does with wifi that has no internet. They're the
  ones who can check in the ordinary way anyway.
- **On the host's phone**, Android may turn its own wifi off while the hotspot
  is on, if the phone can't do both. Mobile data, if there is any, stays.

## Bluetooth, app to app

For attendees who have the uwuHere app: their phone finds the host's over
Google's Nearby Connections and checks in directly (`Mesh.java`), with no
internet needed on either phone. The host page records it the same way as a
hotspot check-in. It needs Google Play services on both phones and one "Nearby
devices" prompt on each. The event has to have Bluetooth turned on in its
settings.

## Taps kept for later

An attendee who taps the host's phone with no connection keeps the tap: the join
page stores its token, shows "Tapped, not sent yet", and sends it as soon as the
phone is back online (`js/join.js`). The service worker serves the join page
offline to anyone who has opened uwuHere before. Someone who never has can't
open the page with no connection at all, so for them it's the hotspot.

The server takes a kept tap for up to 12 hours after it was made, records it at
the tap's time, and marks it "Tapped, sent later" (`api/_lib/tap.js`), even if
the event was paused in the meantime. A tap is refused once the event has ended.
The marking is there because a link passed to someone who wasn't there could
also be sent late; the host can see it.

## Not built, and why

- **Bluetooth from the browser** (Web Bluetooth). Android-specific check-in is
  for attendees with the app, which Bluetooth app to app already covers. In a
  browser, iPhone Safari has none, and Chrome shows a device picker on every
  connection that the page can't skip.
