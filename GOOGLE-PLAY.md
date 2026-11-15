# Putting uwuHere on Google Play

A step-by-step guide to publishing the Android app on Google Play, for the repo as it stands at
2.0.0 (16 November 2026). Google changes its Play rules often: each rule below says where it comes
from, so re-check that page if this date is far behind you.

**What's done in the repo already:** the Play build (`flutter\build-apk.ps1 -Aab`) makes a signed,
shrunk and obfuscated App Bundle with no updater of its own, and checks it; the release notes and
store graphics are written and drawn (`announcements/`, `docs/*-assets/`, `docs/feature-graphic.png`);
the Privacy page is at <https://here.uwuapps.org/privacy>. **What's left is yours:** the account,
the decisions in section 3, and the clicks in Play Console.

## Contents

1. [The short version](#1-the-short-version)
2. [What the Play build is](#2-what-the-play-build-is)
3. [Decisions to make](#3-decisions-to-make)
4. [Step 1: Build the App Bundle](#4-step-1-build-the-app-bundle)
5. [Step 2: Developer account](#5-step-2-developer-account)
6. [Step 3: Create the app](#6-step-3-create-the-app)
7. [Step 4: Store listing](#7-step-4-store-listing)
8. [Step 5: App content (the Dashboard tasks)](#8-step-5-app-content-the-dashboard-tasks)
9. [Step 6: Data safety](#9-step-6-data-safety)
10. [Step 7: Testing tracks, then production](#10-step-7-testing-tracks-then-production)
11. [After launch](#11-after-launch)
12. [Checklist](#12-checklist)

---

## 1. The short version

- Google Play takes an **Android App Bundle** (`uwuhere-<version>.aab`), not the APK on GitHub.
  `release/2.0.0/uwuhere-2.0.0.aab` is ready.
- It's the same app as the GitHub APK, with the same package (`org.uwuapps.here`) and signing key,
  minus the self-updater, which Play forbids: Play updates it instead.
- The bundle is shrunk and obfuscated as Play recommends (R8 for the Java and its libraries, unused
  resources removed, Dart obfuscated with its symbols split off), and carries R8's mapping and the
  native symbol tables, so Play Console's crash reports and its "deobfuscation file" warning are
  covered.
- Play App Signing is required. Give Play **your existing key** (section 3, D1), and installs from
  GitHub and from Play update each other: a phone on a GitHub APK (1.0.x or 2.0.0) takes the Play
  version as an update, its events and host keys kept.
- A new personal developer account must run a **closed test with 12 testers for 14 days** before
  it can publish to everyone. Plan on about three weeks.

## 2. What the Play build is

| | GitHub APK | Play App Bundle |
|---|---|---|
| Built with | `build-apk.ps1` | `build-apk.ps1 -Aab` |
| Updater | Updates page, update bar, downloads and installs the APK | None: Play updates it. The Updates page still lists every version, with **Update on Google Play** |
| `REQUEST_INSTALL_PACKAGES` | Yes | Removed (`flutter/android/app/src/play/AndroidManifest.xml`), and the script checks it's gone |
| Advertising ID (`AD_ID`) | Never: removed from the manifest | The same, and the script checks it's gone |
| Notifications (check-ins, new versions, news) | Yes, with Firebase | Yes, with Firebase |
| Processors | ARM 32 and 64 bit in one APK | Play delivers each device only what it needs, x86_64 Chromebooks included |
| Signed with | `flutter\android.keystore` | The same, as the upload key; Play re-signs with the app signing key (D1) |

The app asks for these permissions, each only when it's needed:

- **Internet** and **network state**: uwuHere's server, same-wifi check-in's pairing, Report a bug,
  the update check.
- **Location** (fine and coarse, foreground only): checking in by location, and a host setting an
  event's spot, when they press the button that needs it. Also what Android 12 and older need for
  Bluetooth scanning and, before 13, for the hotspot. Never in the background, so no background
  location declaration is needed.
- **NFC**: tapping phones, while a host page that uses it is open (install time, never asked).
- **Nearby devices** (Bluetooth scan, advertise, connect; nearby Wi-Fi devices, marked
  `neverForLocation`): Bluetooth check-in from app to app, and the hotspot for no internet, asked
  when a host turns one on or an attendee presses the button.
- **Wi-Fi state** (read and change): the hotspot (Android's local-only hotspot).
- **Post notifications** (Android 13+): only when one of the bell's switches is turned on.
- **Wake lock**: the host's screen held on while check-ins can arrive.

Target SDK: Flutter 3.47's default (36), which Play requires for new apps from 31 August 2026.

## 3. Decisions to make

| | Decision | Recommended |
|---|---|---|
| D1 | **Which key Play signs with.** Your existing key, uploaded once to Play App Signing, keeps the GitHub APK and the Play app able to update each other, and keeps `main-site/.well-known/assetlinks.json` as it is (QR codes and NFC taps keep opening the app). A key Play makes means a Play install can't update a GitHub install (and the other way round): people would uninstall first, and lose the events their phone hosts unless they set passwords. | Your existing key |
| D2 | **Personal or organisation account.** Personal is quicker, but has the 12-tester rule. Organisation needs a registered business (a D-U-N-S number). | The account your other UwU Apps already use |
| D3 | **Countries.** uwuHere isn't tied to a place. | Every country |
| D4 | **Privacy policy URL.** Play requires one: `https://here.uwuapps.org/privacy` (`main-site/privacy.html`, linked from the home page in the site and the apps). Keep it and section 9 saying the same things. | Done |
| D5 | **Category.** Attendance sits in Productivity, Education or Events. | **Productivity** |
| D6 | **Target audience.** Hosts are adults (teachers, organisers); attendees can be any age, but need no app: the website checks them in. | **13 and over** for the app |

## 4. Step 1: Build the App Bundle

In PowerShell, from the project root, with `android.keystore` and `keystore.properties` in
`flutter\` (they're not in git: restore them from your backup; they're the same files the 1.0.x
app was signed with):

```powershell
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab
```

It writes `release\<version>\uwuhere-<version>.aab`, and refuses to finish unless the bundle:

- is signed with the app's key (SHA-256 `EE:0D:A7:D3:D5:30:80:EA:DD:08:41:3D:30:4E:35:E0:11:28:D0:68:55:19:69:8E:6F:F3:ED:31:8D:54:85:7A`);
- has no `REQUEST_INSTALL_PACKAGES` and no `AD_ID` in its manifest;
- carries `BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map` (R8's mapping, which
  Play reads for crash reports) and the stripped symbol tables of `libflutter.so` and `libapp.so`.

Beside it, `uwuhere-<version>-play-mapping.txt` and `-play-symbols.zip` stay on your computer
(git-ignored): with them, `flutter symbolize` reads an obfuscated Dart stack trace from Play's
crash reports.

Every upload needs a higher `versionCode` than any before it. `build-apk.ps1` raises it by itself on
every run (the `+N` in `flutter\pubspec.yaml`), APK or bundle, so a fresh build is always
uploadable; commit `pubspec.yaml` with it. 2.0.0's bundle is version code 6, its APK 5, both above
the Capacitor app's 4.

## 5. Step 2: Developer account

1. Sign in to the Google account that will own the app, with 2-Step Verification on.
2. Register at <https://play.google.com/console/signup>: **US$25, once**, by a card in the account
   holder's name. You must be 18 or older and accept the Developer Distribution Agreement; Google
   may ask for government ID ([registration](https://support.google.com/googleplay/android-developer/answer/6112435)).
   Already have an account for SG Bus Timings or another UwU App? Use that one, and skip to step 3.
3. Choose **personal** (D2), and complete **identity verification**. Allow a few days, and don't
   create the app until it's done. Personal accounts also confirm an Android device through the
   Play Console app.
4. **Developer verification**: creating the app in Play Console registers the package name
   `org.uwuapps.here` to your account ([developer verification](https://developer.android.com/developer-verification)).
   If you registered it on the Android Developer Console for the GitHub APK, Play Console shows it
   as yours already. It covers the GitHub APK too, as both use the same package and key.

## 6. Step 3: Create the app

1. **Create app**: name `uwuHere`, default language **English (United Kingdom)** (`en-GB`), as the
   app and its notes are written, **App**, **Free**, your contact email. Accept the declarations.
2. **Test and release** > **Setup** > **App signing** (or when you create the first release):
   choose **Use a different key** > **Export and upload a key from Java keystore**, and follow
   Play's steps with its PEPK tool and `flutter\android.keystore` (D1). The key's alias is in
   `flutter\keystore.properties`. Use the same key as the **upload key** too. Afterwards, the page
   shows the **app signing key certificate**: its SHA-256 should be the one in section 4. If it
   differs (you let Play make a key), add Play's SHA-256 to `main-site/.well-known/assetlinks.json`
   beside the existing one and deploy, so scanned QR codes and NFC taps still open the app
   ([Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756)).
3. The package name comes from the first bundle you upload. **It's permanent.**

## 7. Step 4: Store listing

**Grow users** > **Store presence** > **Main store listing**
([asset specs](https://support.google.com/googleplay/android-developer/answer/9866151)):

| Field | Limit | uwuHere |
|---|---|---|
| App name | 30 | `uwuHere` |
| Short description | 80 | `Attendance in one tap. People check in when they're near you. No accounts.` (74) |
| Full description | 4,000 | Below |
| App icon | 512 × 512 PNG | `main-site/HAT-512.png` |
| Feature graphic | 1024 × 500, no alpha | `docs/feature-graphic.png` |
| Phone screenshots | 2 to 8 | `docs/phone-assets/01…08` (1620 × 2880) |
| 7-inch tablet screenshots | up to 8 | `docs/tablet-assets/7-inch/01…08` (1620 × 2880) |
| 10-inch tablet screenshots | up to 8 | `docs/tablet-assets/10-inch/01…08` (2880 × 1620) |
| Chromebook screenshots | up to 8 | `docs/desktop-assets/01…08` (2880 × 1620) |
| Category | one | **Productivity** (D5) |
| Tags | up to 5 | Attendance, Events, Education, Productivity, Business (whichever of these Play offers) |
| Contact | email, website | Your email; `https://here.uwuapps.org` |

Upload the screenshots in their numbered order: the first three show in search results.

Full description:

```text
uwuHere takes attendance in one tap. Make an event and get a code, a link and a QR code. People open it and press one big button, and it only counts if they're near you.

FOUR WAYS TO PROVE THEY'RE HERE
Pick one or more for each event:
• Same wifi: their phone connects straight to your screen, so it has to be on the same network
• Location: within a distance you set of where you are. Only the distance is kept, never where they were
• Tapping phones: they hold their phone against yours. Theirs needs no app
• Bluetooth: phone to phone with the uwuHere app, even with no internet

NO INTERNET AT THE VENUE?
Your phone can be the wifi. Show two QR codes: one joins your phone's hotspot, the other opens the check-in page. Check-ins land in your list straight away, and reach uwuHere once you're back online.

THE LIST, LIVE
Watch names arrive as people check in, with how and when. Add someone by hand, remove someone, pause check-ins, and download the list as a CSV for your spreadsheet. People leaving early can say so, once.

FOR THE ROOM
Show the QR code as big as your screen allows, at full brightness. The screen stays on while check-ins can arrive.

NOTHING TO SIGN UP FOR
No accounts. Attendees need no app: any phone's camera and browser will do. An optional password opens your event on another device.

ON YOUR PHONE, TOO
A home screen widget with how many are here and who came last, notifications when someone checks in by location or leaves early, and a widget to check in with a code.

YOUR LOOK
Material You by default: your phone's font and, on Android 12 and later, your wallpaper's colours. Prefer uwuHere's own look? Switch to the UwU Apps theme for its seven brand colours. Light, dark, or time-based.

PRIVATE BY DESIGN
No ads and no analytics in the app. Every event is deleted 7 days after it ends.

ALSO
A short tour of each page the first time you open it, Report a bug with a screenshot and a report ID, the uwuHere apps for Windows, macOS and Linux, and the website at here.uwuapps.org.
```

## 8. Step 5: App content (the Dashboard tasks)

**Policy and programmes** > **App content**
([prepare your app for review](https://support.google.com/googleplay/android-developer/answer/9859455)):

| Task | Answer |
|---|---|
| Privacy policy | Your URL (D4) |
| Ads | **No ads** |
| App access | **All functionality is available without special access**: there are no accounts. (An event's optional password is one the host sets; reviewers make their own events) |
| Content rating | Fill the questionnaire: a productivity tool, no violence, no gambling. **Users can share information**: the names attendees type reach the event's host, and nobody else. There's no chat and no public content |
| Target audience | 13 and over (D6); not designed for children |
| News app | No |
| Government app | No |
| Financial features | None |
| Health | No |
| Advertising ID | **No**: the app has no ads or analytics SDK, and its manifest removes the permission |
| Account deletion | Not required: the app has no accounts and no sign-up |
| Location permissions | Foreground only. If asked: for checking in by location and setting an event's spot, when the person presses the button that needs it, and for Bluetooth and the hotspot on older Android versions, which require it |

## 9. Step 6: Data safety

**App content** > **Data safety**
([form help](https://support.google.com/googleplay/android-developer/answer/10787469)). Data is
"collected" when it leaves the phone to the developer; data used only on the phone isn't.

| Data type | What happens | Declare |
|---|---|---|
| Name (Personal info) | The name an attendee types to check in, kept with the event for its host until the event is deleted | Collected, **required** to check in, App functionality |
| Precise location | An attendee's location is sent once to work out the distance from the host, then dropped (ephemeral). A host's event spot is kept with the event while location check-in is on | Collected, **optional** (only location check-in), App functionality. Not ephemeral overall, because of the host's spot |
| Other user-generated content | Event names, the extra field attendees fill in (such as a student ID), and what's typed in Report a bug | Collected, optional, App functionality |
| Email address | Only if someone leaves an email in Report a bug as the way to reach them | Collected, optional, App functionality |
| Photos | Up to three pictures added to Report a bug, sent on to Telegram | Collected, optional, App functionality |
| Device or other IDs | A SHA-256 of a random ID the app makes, so one phone checks in once; and, with notifications on, Firebase subscribes the phone to topics through Google's servers | Collected, required to check in, App functionality (and fraud prevention) |
| Diagnostics (App info and performance) | Report a bug adds the app's version, the device and system as the app describes them, and the page on show, all shown before it's sent | Collected, optional, Analytics |
| IP address | PeerJS's introduction service sees both devices' IP addresses for same-wifi check-in; Report a bug counts reports per IP address for a minute (and an hour, with Redis) to stop floods | Disclose under the privacy policy |
| Contacts, calendar, messages, health, financial info, web history, files | Not used | Not collected |

Other answers:

- **Encrypted in transit**: **Yes** (HTTPS for the site's API, DTLS for same-wifi check-in's WebRTC
  channel, Nearby Connections' encryption for Bluetooth).
- **Can people ask for data to be deleted?** **Yes**: every event and its list is deleted 7 days
  after it ends (30 after it was made if nobody ends it); a host can remove anyone at any time; and
  anyone can ask by email, as the Privacy page says.
- **Shared with third parties?** No: Supabase (the database), Vercel (the server), Firebase and
  Telegram (which delivers bug reports to you) are service providers working for uwuHere, which
  Play doesn't count as sharing. An attendee's name reaching the event's host is the app's purpose,
  which the form covers as collection for app functionality.
- Check the SDKs' own notes in the [Play SDK Index](https://play.google.com/sdks): Firebase
  Messaging, Google Play services (Nearby), flutter_webrtc, geolocator, WorkManager.

## 10. Step 7: Testing tracks, then production

1. **Internal testing**: **Test and release** > **Testing** > **Internal testing** > **Create new
   release**, upload `uwuhere-2.0.0.aab`, paste the release notes from
   `announcements/play-release-notes-2.0.0.md`, and add yourself and a few testers by email. No
   review in the usual case. Use it to check:
   - a phone with the **GitHub APK** installed takes the Play version as an update, its events kept
     (only with D1's existing key, and only when the Play bundle's `versionCode` is higher than the
     APK's: 2.0.0's is, as the bundle is built after the APK);
   - the Updates page shows **Update on Google Play**, and there's no update bar;
   - a QR code scanned with the camera opens the check-in page in the app (verified links);
   - tapping phones, Bluetooth and the hotspot between two test phones.
2. **Closed testing**, for a new personal account
   ([testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)):
   a closed track with **at least 12 testers opted in for 14 days in a row**. Invite 15 or so (the
   UwU Apps Telegram channel is a good place), so a few dropping out doesn't restart the clock.
3. **Apply for production** from the Dashboard once that's met, and answer its three sections.
   Google usually replies within seven days.
4. **Production**: create the release (the same bundle, or a newer one), the release notes, the
   countries (D3), and **Start rollout**. The first review can take a few days.

## 11. After launch

- **Every update**: raise the version name, `build-apk.ps1 -Aab` (the code goes up by itself),
  upload to a track, paste `announcements/play-release-notes-<version>.md`, roll out. The GitHub
  release goes on as before with the APK (`release/README.md`).
- **Point people to Play**: add the Play link to the site and the GitHub release notes once it's
  live.
- **Target API each year**: Play raises the required target SDK every August. Upgrading Flutter
  raises it; check `targetSdk` in the built bundle's manifest
  ([target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878)).
- **Crashes**: Play Console > **Quality** > **Android vitals**. Java stack traces are readable thanks
  to the mapping in the bundle; for Dart ones, `flutter symbolize -i <trace> -d <unzipped
  -play-symbols.zip>`.

## 12. Checklist

- [ ] D1–D6 decided; the privacy policy page live (deploy the site)
- [ ] `flutter\android.keystore` and `flutter\keystore.properties` backed up somewhere safe
- [ ] `uwuhere-<version>.aab` built with `-Aab`, its checks passed
- [ ] Developer account registered and verified
- [ ] App created; App Signing set up with the existing key; its SHA-256 matches section 4
- [ ] Store listing: text, icon, feature graphic, phone, tablet and Chromebook screenshots
- [ ] App content tasks answered; Data safety filled
- [ ] Internal test installed and checked
- [ ] Closed test: 12+ testers, 14 days; production applied for and approved
- [ ] Production rolled out; the site links to Play
