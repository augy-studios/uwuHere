# Porting table

Each part of the site (`main-site/`), where it lives in the app, and how it stands. Storage keys,
the API's shapes, the same-wifi protocol and the words are the site's own throughout;
`test/logic_test.dart` checks the ported logic against the site's answers, and the Playwright suite
(`e2e/tests/`) drives the real screens against the site's API shapes.

| Site | App | Status |
|---|---|---|
| `js/store.js` every `uwuhere.*` key | `lib/data/here_store.dart`, `lib/data/store.dart` | Done, the same keys and JSON |
| `js/api.js` one answer shape, offline as an answer | `lib/api/api.dart` | Done |
| `js/p2p.js` PeerJS host and attendee, STUN only | `lib/p2p/here_p2p.dart`, `peer.dart`, `binarypack.dart`, `ice.dart` | Done: PeerJS's broker and BinaryPack, so the app's host page takes the site's check-ins and the other way round. No TURN, ever |
| `index.html`, `js/home.js` join, your events, making an event | `lib/features/home/` | Done |
| `host.html`, `js/host.js` the host page: polling, outbox, P2P, tap, Bluetooth, hotspot, CSV, settings, password, end | `lib/features/host/` | Done |
| `join.html`, `js/join.js` the check-in page: tap, Bluetooth, same wifi, location, held taps, leaving early | `lib/features/join/` | Done |
| `js/password.js` the checklist | `lib/data/password.dart` | Done (the breach check stays on the server) |
| `js/colour-picker.js` the wheel, brightness and hex box | `lib/widgets/colour_picker.dart` | Done |
| `js/qr.js` | qr_flutter | Done |
| `js/geo.js` one reading, with sentences | `lib/data/geo.dart` (geolocator; Linux's Wi-Fi fallback in `lib/desktop/location.dart`) | Done |
| `js/ui.js` ink, label size, times, armed buttons | `lib/data/format.dart`, the screens | Done |
| `js/tray.js` the Edge Tray | `lib/widgets/edge_tray.dart` | Done, under the same key |
| `js/theme.js` brand colours, light, dark, time-based | `lib/theme/theme.dart`, `lib/features/theme/theme_sheet.dart` | Done, plus Material You (Android) and the system's glass (desktop) |
| `js/tour.js` first-visit tours | `lib/features/tour/tour.dart` | Done, under the same keys |
| `js/bug-report.js` Report a bug, Screenshot a page | `lib/features/bug/bug_report.dart` | Done: Screenshot a page takes the whole page |
| `js/sw-update.js`, `js/app-update.js` the update bar | `lib/features/update/update_bar.dart`, `lib/desktop/updater.dart` | Done, as the app's own updater and Updates page (Android), and the desktop's |
| `js/app-bridge.js` the Capacitor bridge | `lib/native/bridge.dart`, `android/…/MainActivity.java` | Replaced: one method channel, the old HerePlugin's methods kept |
| `js/app-notify.js` the bell, host alerts | `lib/features/notify/` | Done, the same topics |
| `js/app-widget.js` the home screen widget | `lib/features/widget/app_widget.dart`, `EventWidget.java`, `WidgetData.java` | Done |
| `HerePlugin.java`, `TapService`, `Mesh`, `Hotspot`, `LocalServer` | `android/app/src/main/java/org/uwuapps/here/` | Moved across, behind the new bridge |
| `UpdateActivity.java` | the Updates page | Replaced |
| `sw.js` offline | everything kept on the device | The host page and its list open offline |
| `/join?id=`, `/host?id=`, `/#join`, `/#host`, `uwu://here/` | `lib/app/links.dart`, `AndroidManifest.xml` (verified links, NFC tags) | Done |
| `api/app-release.js` (with `history`), `api/push/release.js` | the site's side of the apps | Extended in 2.0.0 for the Updates page |
| The 1.0.x app's data (WebView) | `lib/data/migrate.dart`, `MainActivity.migrate` | Done, once, never over newer values |
