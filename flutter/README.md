# uwuHere's apps

Android, Windows, macOS and Linux from one Flutter project, with the same features, words, stored
data and API as the website in `../main-site/`, which stays the specification
(`docs/flutter-android-app-spec.md`, `docs/flutter-desktop-app-spec.md`,
`docs/desktop-features-spec.md`, `docs/page-tour-spec.md`). `PORTING.md` maps each part of the site
to its Dart. They replace the 1.0.x Capacitor app (the site in a WebView), and update it in place:
same package, same key, a higher version code, and its stored events brought across once.

```text
lib/
  main.dart, run.dart     start-up: the store, the old app's data brought across once, the bridge
                          (or the desktop's host), the theme, then the app
  app/                    the shell: the three pages (home, host, check-in), links, navigation
  api/                    the site's /api/*, and whether the network's there
  data/                   storage under the site's keys, codes, the password checklist, the CSV,
                          location, and the migration from the 1.0.x app
  p2p/                    same-wifi check-in: PeerJS over WebRTC, STUN only (the site's p2p.js)
  features/home/          the home page: join, your events, making an event
  features/host/          the host page: its controller (host.js) and screen, settings, QR, end
  features/join/          the check-in page: its controller (join.js) and screen
  features/               notify (the bell), widget (the home screen widget's data), theme, tour,
                          bug (Report a bug), update (the Updates page)
  native/bridge.dart      the one way to platform code: Native.call / has / on
  desktop/                the desktop layer: window, tray, title bar, updater, widgets, polling
  theme/                  the UwU Apps look, Material You (Android) and the system's glass
                          (desktop: Fluent 2, macOS Tahoe, Frosted Glass); the site's icons
  widgets/                the Edge Tray, the big button, the colour wheel, the page frame
android/                  the Gradle project: app/ (Java for NFC taps, Bluetooth, the hotspot, the
                          widgets, the updater, FCM), behind one bridge (MainActivity.java)
windows/ macos/ linux/    the runners, each with a small native channel (Jump List, Dock…)
installers/               NSIS, WiX, .deb/.rpm/AppImage and .dmg scripts, and the update files
e2e/                      the screens in a browser, driven by Playwright (e2e/README.md), and the
                          store's screenshots (e2e/shots/)
test/                     unit tests for the ported logic and the release notes
tool/                     make_icons.py: every icon from docs/assets/uwuhere-icon.svg
```

## Building

**Android**, from the project root in PowerShell, with `android.keystore` and
`keystore.properties` in `flutter\` (the 1.0.x app's key, not in git: restore them from your
backup):

```powershell
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1        # the APK, for GitHub
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab   # the App Bundle, for Google Play
```

Each run raises the version code (the `+N` in `pubspec.yaml`) by one, builds, checks the signature
against the app's key, and copies the file to `release\<version>\`. Both are shrunk and obfuscated
(R8 and Dart's `--obfuscate`); the mapping and Dart symbols stay beside them, git-ignored, for
reading crash reports. The bundle has no updater of its own (Play updates it), which the script
checks. Raise the version name yourself for a new release.

Notifications need `android\app\google-services.json`: `FIREBASE-SETUP.md`.

**Desktop**: GitHub Actions builds every platform on publish (`.github/workflows/build-desktop.yml`).
To try one locally: `flutter build windows` (or `macos`, `linux`), and `flutter run -d windows`.

**Icons**: `python tool/make_icons.py` makes every icon (the site's `HAT-*.png` and
`favicon.ico`, Android's launcher, the desktops') from `docs/assets/uwuhere-icon.svg`.

## Testing

```powershell
cd flutter
flutter analyze
flutter test                       # the ported logic and the release notes
cd e2e; npm install; npx playwright install chromium
npm run build; npm test            # the real screens in Chromium, and the website (e2e/README.md)
```
