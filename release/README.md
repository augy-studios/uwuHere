# Releases

Each version's Android builds live here, one folder per version, as SG Bus Timings keeps them:

```text
release/2.0.0/
  uwuhere-2.0.0.apk                   Android, for GitHub          flutter\build-apk.ps1
  uwuhere-2.0.0.aab                   Android, for Google Play     flutter\build-apk.ps1 -Aab
  uwuhere-2.0.0-mapping.txt           reads the APK's crashes      not in git, not uploaded
  uwuhere-2.0.0-symbols.zip           reads its Dart crashes       not in git, not uploaded
  uwuhere-2.0.0-play-mapping.txt      the same for the bundle      not in git (Play has its own copy)
  uwuhere-2.0.0-play-symbols.zip      the same for the bundle      not in git
release/1.0.0/ … release/1.0.3/       the Capacitor app's APKs, as they were published
```

The APK and the App Bundle are committed with the code they were built from. GitHub refuses any
file over 100 MB: one that big is listed by name in the root `.gitignore` and goes only on the
GitHub release (none so far). The desktop installers (`.exe`, `.msi`, `.dmg` and `.zip`, `.deb`,
`.rpm`, `.AppImage`, and the `latest*.yml` update files) are built by GitHub Actions and live only
on the GitHub release.

All of them share one version number and one GitHub release, tagged `android-v<version>`. Keep to
that prefix: it's how the Android app's updater (and the 1.0.x app's) finds its releases.

## Publishing a version

1. **Raise the version name** in `flutter/pubspec.yaml` (`2.0.0+N` becomes `2.0.1+N`). Leave the
   `+N`: every build raises it by one by itself, as Google Play refuses a version code it has seen,
   and a phone only takes a higher one as an update.
2. **Build the Android files**, from the project root in PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1        # the APK
   powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab   # the App Bundle
   ```

   Each checks its signature against the app's key, and the bundle that nothing of the updater or
   the advertising ID is left in it. Both are shrunk and obfuscated, as Google Play asks.
   **Then open the APK on a phone or emulator** before going on (`adb install -r` it, open it, make
   an event, turn a notification on). The Playwright suite runs the app in a browser, never the
   shrunk build, and R8 can remove something Android only asks for by name: 2.0.0 closed as soon as
   it opened for that reason (`flutter/android/app/proguard-rules.pro`).
3. **Deploy the site first** if this release needs anything new from it (the Updates page reads
   `/api/app-release`, Report a bug posts to `/api/bug-report`).
4. **Commit the code, `pubspec.yaml` and `release/<version>/`** and push.
5. **Make the release**, with the APK attached **before** publishing:
   - **Releases** > **Draft a new release**, tag `android-v<version>` (**Create new tag on
     publish**, target `main`), title `uwuHere <version>`.
   - Paste `announcements/release-notes-<version>.md` into **Describe this release**.
   - Attach `uwuhere-<version>.apk`, and wait for it to finish uploading. Never the `.aab`: that's
     for Google Play (`GOOGLE-PLAY.md`).
   - Tick **Set as the latest release**, then **Publish release**.

   Or with the GitHub CLI, the same in three steps (a draft first, so the APK is there before the
   "new version" push fires on publish):

   ```powershell
   gh release create android-v2.0.1 --draft --title "uwuHere 2.0.1" --notes-file announcements/release-notes-2.0.1.md release/2.0.1/uwuhere-2.0.1.apk
   gh release view android-v2.0.1 --json assets   # the APK's digest matches: Get-FileHash release/2.0.1/uwuhere-2.0.1.apk
   gh release edit android-v2.0.1 --draft=false --latest
   ```

6. GitHub Actions (**Build desktop apps**) builds Windows, macOS and Linux from the tag and adds
   their installers and `latest*.yml` files to the release, about 20 minutes later. Or run it by
   hand first with the tag, and it makes a draft release with them, for the APK to join.
7. Post `announcements/announcement-<version>.md` to the UwU Apps Telegram channel, and upload the
   bundle to Google Play with `announcements/play-release-notes-<version>.md`.

`https://github.com/augy-studios/uwuHere/releases/latest` always points at the newest one.

## How phones and computers hear about it

- **Android (GitHub APK)**: within ten minutes the app's bar says the version is out (from
  `/api/app-release`, which skips drafts, pre-releases, tags that aren't `android-v*` and releases
  whose APK hasn't finished uploading), and the Updates page downloads it, checks GitHub's SHA-256
  and installs it. With **New versions of the app** on, a notification arrives the moment it's
  published (`main-site/api/push/release.js`, `flutter/FIREBASE-SETUP.md`): that's why the APK
  has to be attached before **Publish release**. The 1.0.x Capacitor app hears the same way and
  installs 2.0.0 over itself, its events kept.
- **Android (Google Play)**: Play updates it.
- **Windows, macOS, Linux AppImage**: the app reads the `latest*.yml` files on the newest release as
  it opens and every hour, downloads the new version and offers **Restart to update**.
- **Windows `.msi`, Linux `.deb` and `.rpm`**: a notification says it's out, with a link here.

## Before you share it

- **Never upload `android.keystore`, `keystore.properties`, `google-services.json` or the Firebase
  service account key**: only the APK. The repository has to be public for others to download it.
- Keep the `-mapping.txt` and `-symbols.zip` files: they're the only way to read the app's crash
  reports back (`flutter symbolize`).

## If something goes wrong

| What happens | What to do |
|---|---|
| "App not installed" on the phone | A copy signed with a different key is installed, such as a debug build. Uninstall uwuHere, then install again. |
| "App not installed as package appears to be invalid" | The download didn't finish. Download it again. |
| Play Protect warns about the app | Tap **More details** > **Install anyway**. |
| You uploaded the wrong file | On the release, click **Edit**, delete the file with the bin icon, attach the right one, and click **Update release**. The app checks the file against GitHub's checksum, so phones won't install a mismatch. |
| No update bar in the app | The tag doesn't start `android-v`, the release is a draft or pre-release, or it's been under 10 minutes. `https://here.uwuapps.org/api/app-release` shows what phones see. |
| No notification | Check the webhook's **Recent Deliveries** in GitHub: each one shows why it did or didn't send (`flutter/FIREBASE-SETUP.md`). |
| The desktop installers didn't appear | Open the repository's **Actions** tab, **Build desktop apps**: run it by hand with the tag if it didn't start, or read the failed job's log. |
