# uwuHere for Android

The Android app, `org.uwuapps.here`: the web app at here.uwuapps.org in
[Capacitor](https://capacitorjs.com)'s WebView (`capacitor.config.json`, `server.url`). The
site's own updates reach it at once, so the app only needs building again for its native parts.
Those are the things a web page can't do, which the page reaches through Capacitor's bridge
(`main-site/js/app-bridge.js`).

It's shared as an APK file through GitHub Releases (see `release/README.md`), and updates
itself from there.

## What it adds to the site

| Feature | Native side (`native/app/src/main/java/org/uwuapps/here/`) | Site side (`main-site/`) |
|---|---|---|
| **The host's screen stays on** while same-wifi check-in is ready. In Chrome the page uses the Screen Wake Lock API, which Android's WebView doesn't have | `HerePlugin.keepAwake` | `js/host.js` (`updateWakeLock`) |
| **The big QR code at full brightness** while it's up, so the back of a room can scan it. Only the app's window: the phone's own setting is untouched | `HerePlugin.brightness` | `js/host.js` (`showQr`, `uwu:modalclose`) |
| **The CSV saved to Downloads** (Android 10 and later), or wherever you pick (Android 7 to 9). The WebView can't download a file the page made itself, so without this the CSV button would do nothing | `HerePlugin.saveFile` | `js/host.js` (`downloadCsv`) |
| **Updating itself** from GitHub Releases: a bar at the top of the page when a new version is out, and the Edge Tray's download button, "Check for updates", which also checks for a new site version. Both use Android's own installer | `UpdateActivity` | `js/app-update.js`, `js/sw-update.js`, `api/app-release.js` |
| **Notifications**, opt-in from the bell in the Edge Tray: check-ins by location and early leavers at your events, new versions of the app (pushed the moment a release is published), and news you send from the Firebase console | `HerePlugin.setTopic`, `HerePlugin.watchEvent` (FCM topics), `Notifications`, Capacitor's PushNotifications | `js/app-notify.js`, `api/_lib/alerts.js`, `api/push/release.js`, `api/_lib/fcm.js` |
| **The site's own links** (`https://here.uwuapps.org/...`, verified by `.well-known/assetlinks.json`), so scanning a host's QR code with the phone's camera opens the check-in button in the app. Also `uwu://here/` links, such as `uwu://here/join?id=BCD234` | `MainActivity` | none |
| **Location** for checking in and setting the event's spot, with Android's own permission prompt | the manifest's location permissions; Capacitor's WebView asks | `js/geo.js` (the sentence for a refusal) |
| **Tapping phones**: the host's phone answers as an NFC tag, handing each phone that touches it the join link with a one-time token, so attendees check in with no app, in their browser. A "Phone tapped" note on the host page each time | `TapService`, `HerePlugin.tap` | `js/host.js`, `js/join.js`, `api/_lib/tap.js` |
| **Bluetooth check-in, app to app**: an attendee who has the app checks in phone to phone with the host's, over Google's Nearby Connections, with no internet needed on either | `Mesh`, `HerePlugin.bluetooth`, `HerePlugin.meshCheckIn` | `js/host.js`, `js/join.js` |
| **Checking in with no internet**: the host's phone becomes a wifi hotspot serving a check-in page of its own, for attendees with no signal, iPhones included. Two QR codes on the host page: join the wifi, open the page. See `OFFLINE-CHECKIN.md` | `Hotspot`, `LocalServer`, `res/raw/hotspot_page.html`, `HerePlugin.hotspot` | `js/host.js` |
| **Home screen widgets**. "Your event": the event this phone is hosting, with how many are here, how many left early, who checked in last and its code; tapping it opens the host page. It refreshes from its own button and every 15 minutes while the event is on, with the app closed. "Check in": two buttons, **Check in** (the home page's code box) and **Host** (its new event form) | `EventWidget`, `WidgetData`, `WidgetWorker`, `ShortcutWidget`, `HerePlugin.widget` | `js/app-widget.js`, `js/host.js`, `js/home.js` (`/#join`, `/#host`) |
| **No status bar**, so the page has the whole screen; a swipe down from the top shows it for a moment, its icons following the page's light or dark mode, not the phone's. The user agent's `uwuHereApp/2` tells the page there's no bar to leave room for (1.0.0, `uwuHereApp/1`, still has it) | `MainActivity`, Capacitor's SystemBars | `js/app-bridge.js`, `css/app.css` (`data-statusbar`) |

The website and PWA lose nothing: everything a browser can do stays as it was, and these only
switch on when the page is running in the app. The bell and the update button are made by the
page only in the app, so a browser never sees them.

Things the app deliberately doesn't do:

- **Keep running in the background.** Same-wifi check-in needs the host's page open, as on the
  web; the app keeps the screen on rather than starting a background service, which Android
  would show as a permanent notification and may still stop. The one exception is the "Your
  event" widget's refresh: a short WorkManager job every 15 minutes, only while that widget is on
  the home screen and its event hasn't ended, and only with a connection.
- **Scan QR codes itself.** The phone's camera already does, and the site's links open in the
  app, so it needs no camera permission.
- **Background location.** Location is read once, when someone presses the button.

### Permissions

| Permission | Asked | For |
|---|---|---|
| Location (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`) | The first time someone checks in by location, or a host sets the event's spot | Checking in by location |
| Notifications (`POST_NOTIFICATIONS`) | Only when you turn on a switch under the bell in the Edge Tray (Android 13 and later) | Check-ins, new versions, news |
| Install unknown apps (`REQUEST_INSTALL_PACKAGES`) | The first update | `UpdateActivity` |
| NFC (`NFC`) | Not asked: Android grants it at install | Tapping phones (`TapService`) |
| Nearby devices (`NEARBY_WIFI_DEVICES`), Android 13 and later | The first time a host starts the hotspot, or Bluetooth check-in | The hotspot (`Hotspot`), and Bluetooth phones moving to wifi once they've met (`Mesh`). Never used to find where anyone is |
| Nearby devices (`BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`), Android 12 and later | One prompt with the above, when a host allows Bluetooth check-in or an attendee first presses the button | Bluetooth check-in (`Mesh`) |
| Location, Android 12 and earlier, for Bluetooth | The same moment, if not already allowed | Android wants it for finding Bluetooth devices there; on Android 11 and earlier it also has to be switched on |
| Location, Android 8 to 12 | The same, if not already allowed for checking in by location | The hotspot: Android wants it there instead of nearby devices |
| Wifi state (`ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`) | Not asked: Android grants them at install | The hotspot |
| Internet | Not asked: Android grants it | The site itself |

Keeping the screen on and the QR code's brightness need no permission, and neither does saving
to Downloads on Android 10 and later, or the widgets.

The "Your event" widget keeps the event's host key in the app's own storage, as the page keeps it
in the WebView's, so it can ask the server for the list. It shows the name of whoever checked in
last on the home screen; a host who'd rather not can leave the widget off.

If the app ever goes on Google Play, that build has to drop `UpdateActivity` and
`REQUEST_INSTALL_PACKAGES`, since Play updates apps itself.

## The project

```text
android/
  package.json, package-lock.json   Capacitor and its push plugin
  capacitor.config.json             the site's address, and where the native project is
  www/offline.html                  shown when the site can't load at all (first launch offline)
  native/                           the Android Studio / Gradle project
  build-apk.ps1                     builds the signed APK into release/<version>/
  FIREBASE-SETUP.md                 setting up notifications
```

`npx cap sync android`, which the build script runs, copies `www/` and the config into
`native/` and links the plugins from `node_modules`. What it writes is kept out of git.

## Build the APK

From the project root, in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File android\build-apk.ps1
```

That one command:

1. On the very first run, makes the signing key (`android.keystore` and `keystore.properties`)
   and writes its fingerprint into `main-site/.well-known/assetlinks.json`, replacing the
   template's placeholder.
2. Installs the npm packages if they're missing, and runs `npx cap sync android`.
3. Builds the release APK with Gradle, signed with that key.
4. Checks the signature against the fingerprint in `assetlinks.json`.
5. Copies the result to `release/<version>/uwuhere-<version>.apk`, with `<version>` taken from
   `versionName` in `native/app/build.gradle`.

(`npm run build` from inside `android/` runs the same script.)

It needs a JDK 21 or later (it finds the newest under Program Files, or `JAVA_HOME`) and the
Android SDK (`ANDROID_HOME`, the one Bubblewrap left in `~/.bubblewrap`, or Android Studio's in
`%LOCALAPPDATA%\Android\Sdk`). Gradle fetches any SDK platform it's missing.

**For a new version**, raise both of these in `native/app/build.gradle` first:

```groovy
versionCode 3          // a whole number, one higher each release: phones only update to a higher one
versionName "1.0.2"    // what people see, and the release folder's name
```

If `release/<version>/` already has an APK, the script warns and replaces it.

Without `native/app/google-services.json` the app builds and works, but has no notifications,
and the bell stays hidden. See `FIREBASE-SETUP.md`.

To try changes on a phone over USB, open `native/` in Android Studio and run it, or use
`native\gradlew.bat installDebug` with the phone plugged in and USB debugging on. A debug build
is signed with Android Studio's debug key, so uninstall it before installing a release APK.

## The first build: back up the key

The first build prints the new key's fingerprint and asks for two things:

1. **Back up `android\android.keystore` and `android\keystore.properties`** somewhere safe and
   private, such as a password manager. Both are kept out of git. An APK signed with a
   different key can't update one already installed, so losing them means every user has to
   uninstall and reinstall.
2. **Commit and deploy `main-site/.well-known/assetlinks.json`**. It lists this key's
   fingerprint, which is what lets the site's links, and so a host's QR code, open in the app.

From then on, the script refuses to build if the keystore is missing (restore it from your
backup), and refuses an APK signed with any key other than the one `assetlinks.json` names.

## Google's developer verification

From 30 September 2026, Android in Singapore (with Brazil, Indonesia and Thailand) checks that
apps come from a verified developer, starting with installs through participating app stores,
with more to follow in 2027. To stay ahead of it and keep Play Protect from warning about the
APK:

1. Sign up on the [Android Developer Console](https://developer.android.com/developer-verification/guides/android-developer-console),
   or use the account you made for SG Bus Timings.
2. Register the package `org.uwuapps.here` with the SHA-256 fingerprint in
   `assetlinks.json`.

Check [Google's guide](https://developer.android.com/developer-verification/guides) for the
current steps; they were still settling in October 2026.

## Install it

Copy the APK to the phone and open it. Android asks to allow installing apps from wherever it
was opened (Files, Chrome, Telegram); allow it once. After that, the app updates itself.

## Checking it by hand

On a phone with the app installed:

- **Host**: make an event with same wifi on. The screen stays on while "Ready for same-wifi
  check-ins" shows, and sleeps as usual once you end the event or leave the page.
- **QR**: "Show the QR code big" turns the screen to full brightness; closing it (the X, the
  backdrop, or Back) puts it back.
- **CSV**: the CSV button says "Saved to Downloads as uwuhere-CODE-DATE.csv", and the file opens
  from the Files app.
- **Links**: scan the QR code with the phone's camera. It opens the check-in button in the app,
  not the browser. If it opens the browser, `assetlinks.json` isn't deployed with this key yet.
- **Location**: check in by location. Android asks for location once; refuse it, and the page
  says to allow it in Android's settings.
- **Updates**: the Edge Tray's circled download button says you have the newest version.
- **Widgets**: add "Your event" before hosting anything: "No event yet", and a tap opens the
  home page at "Host an event". Open an event's host page: the widget shows it within a second.
  Check in by location from another phone, then tap the widget's refresh button: "Refreshing…",
  then one more here. End the event: "Ended". In airplane mode, refresh says "Offline, as of …".
  Shrink it to one row high: the detail line goes, then the code. "Check in": **Check in** opens
  the code box, **Host** the new event form, both from the app closed and from another page in
  it. Switch the phone to dark mode: both widgets follow.
- **Notifications** (with Firebase set up): turn on "Check-ins to my events", close the app, and
  check in by location from another phone. "Name checked in by location" arrives within
  seconds.

## Changing it

- **The site's address, the user agent, the status bars**: `capacitor.config.json`, then
  `npx cap sync android`.
- **Permissions, activities, links**: `native/app/src/main/AndroidManifest.xml`.
- **Something new the page can ask the app for**: a `@PluginMethod` in `HerePlugin`, called
  from the page with `AppBridge.call("Here", "method", {...})`. Add a word to `info`'s
  `features` so the page can tell builds with it from builds without.
- **A Capacitor plugin from npm**: `npm install` it here, then `npx cap sync android`; the page
  reaches it the same way.
- **Upgrading Capacitor**: raise the `@capacitor/*` versions in `package.json` together (the
  push plugin's numbers run on their own, so take its newest for that Capacitor), `npm install`,
  `npx cap sync android`, and compare `native/` with a fresh `npx cap add android` for template
  changes.

`npm audit` reports a moderate advisory in `uuid`, through `@capacitor/cli`'s iOS tooling
(`xcode`). It's a build-time tool that never reaches the app, and the suggested fix downgrades
Capacitor, so leave it until Capacitor updates it.
