# Setting up Firebase Cloud Messaging for the Android app's notifications

The Android app's notifications come through **Firebase Cloud Messaging (FCM)**, Google's push
service for Android. There are three kinds, and people turn each on with the bell in the Edge
Tray (the Updates page has the second's switch too):

| Notification | Sent by | FCM topic |
|---|---|---|
| **Check-ins to my events**: "Alex checked in by location. 12 checked in so far." and "Sam left early.", at events this phone hosts. Tapping it opens that event's host page | The site's server, as the check-in or the early leave arrives (`main-site/api/_lib/alerts.js`) | `uwuhere-host-<40 hex>`, one per event |
| **New versions of the app**: "Version 2.0.1 of uwuHere is out", the moment you publish a release. Tapping it opens the Updates page | The site's server (`main-site/api/push/release.js`), called by a GitHub webhook | `uwuhere-releases` |
| **News from uwuHere**: whatever you want to say, whenever | You, from the Firebase console | `uwuhere-news` |

```text
You publish a release on GitHub (android-v2.0.1, APK attached)
  → GitHub calls the site's webhook: https://here.uwuapps.org/api/push/release
  → the site checks GitHub's signature, and sends "Version 2.0.1 of uwuHere is out" to uwuhere-releases
  → every phone that turned on "New versions of the app" gets it, even with the app closed
  → tapping it opens the Updates page, where Update installs it
```

A phone joins a topic when its switch is turned on, so the server keeps no list of phones and
there's no database table for it. An event's topic is named from its host key, which only the
host's phones hold, so nobody else can name it and listen in on who checks in. The topics carry
the `uwuhere-` prefix because topics are shared by every app in a Firebase project.

How the app handles them (`flutter/android/app/src/main/java/org/uwuapps/here/`):

- `MainActivity.java`, the **Here** plugin's `topics`, `setTopic` and `watchEvent`: joining and
  leaving topics, asking Android 13+'s notification permission when a switch is turned on, and
  remembering each switch. The host page names its event whenever it has it from the server
  (`lib/features/notify/host_alerts.dart`).
- `MessagingService.java`: shows a push that arrives while the app is in front, where Android
  wouldn't. In the background Android shows it itself, on the channel the push names.
- `Notifications.java`: the three channels, **Check-ins** (quiet), **New versions** and **News
  from uwuHere**, each its own switch in Android's settings for the app.
- `MainActivity.linkOf`: a tapped notification opens the event's host page
  (`type=checkin`, `code`) or the Updates page (`type=release`).

**If you set this up for the 1.x app** (`android/FIREBASE-SETUP.md` before 2.0.0), everything
carries on: the Firebase app, `google-services.json`, the service account, Vercel's variables, the
GitHub webhook, the topics and their channels are the same, and 2.0.0 keeps each phone's switches
(the same names, in the same place). Copy `google-services.json` from `android\native\app\` into
`flutter\android\app\` (done already on the computer that built 2.0.0), then skip to section 6
to build it and section 7 to check it works.

The desktop apps don't use any of this: they look at your events every minute while they run
(`lib/desktop/alerts_poll.dart`), and check GitHub for new versions themselves
(`lib/desktop/updater.dart`). The Google Play build uses it too, though Play also tells people
about updates itself.

uwuHere is in the shared **UwU Apps** Firebase project, as an app of its own beside SG Bus
Timings, uwuFix and the rest. Only FCM is used: no Analytics, no database, nothing else. It's
free.

Until this is done, the app works fully, but the bell in the Edge Tray shows only on the desktop,
and the Updates page has no **New versions of the app** switch.

It takes about 20 minutes, and covers four things:

| What | Where it goes | Secret? |
|---|---|---|
| `google-services.json`, which tells the app which Firebase project it belongs to | `flutter/android/app/` | No, but kept out of git anyway |
| uwuHere's service account key (`….json`), which lets the site's server send pushes | Vercel, as `FIREBASE_SERVICE_ACCOUNT` | **Yes.** Anyone with it can push to phones with any app in the UwU Apps project |
| A webhook secret, which proves a "release published" call really came from GitHub | GitHub and Vercel, as `GITHUB_WEBHOOK_SECRET` | **Yes** |
| A GitHub token (optional), which raises GitHub's rate limit for the release lookups | Vercel, as `GITHUB_TOKEN` | Yes, though it can do nothing but read |

Only the first is needed for the bell to appear. Without the second, the switches work but
nothing is ever sent; without the third, check-ins and news still arrive, but not new versions.

## How the shared project fits together

```text
Firebase project "UwU Apps"
  Android app  org.uwuapps.here        <- this app
  Android app  org.uwuapps.sgbus       <- the other UwU Apps, each added the same way
  Service account  uwuhere-push        <- this site's server's key: FCM only
  Service account  sgbus-timings-push  <- one per other app's server
```

- **One Android app entry per app**, each with its own package name.
- **Topics are shared** by every app in the project: each app joins only topics with its own
  prefix, so only uwuHere joins `uwuhere-*`.
- **One service account per server**, allowed only to send through FCM. Each can be deleted
  without touching the others. Don't use the project's "Firebase Admin SDK" key: it can do
  anything in the project, for every app in it.

## 1. Add uwuHere to the UwU Apps project, and get `google-services.json`

1. Open <https://console.firebase.google.com> and pick the **UwU Apps** project. (No project yet?
   **Create a project**, name it `UwU Apps`, leave Google Analytics off for uwuHere's sake, and
   **Create project**.)
2. Click the gear by **Project Overview**, then **Project settings** > **Your apps** > **Add
   app** > **Android**.
3. **Android package name**: `org.uwuapps.here`. It has to be exactly this.
4. **App nickname**: `uwuHere`. Leave **Debug signing certificate SHA-1** empty: FCM doesn't need
   it.
5. Click **Register app**.
6. Click **Download google-services.json**. Save it as `flutter\android\app\google-services.json`
   in this project, beside `build.gradle.kts`.
7. Click **Next** through the remaining steps without changing anything. The project already has
   what they describe: `android/settings.gradle.kts` declares the Google services plugin, and
   `android/app/build.gradle.kts` applies it whenever the file is there.

The file lists every app in the project, and the build takes the `org.uwuapps.here` entry from
it. Download it **after** registering uwuHere, or the build stops with "No matching client found
for package name".

## 2. Check FCM's API is on

In Firebase, open **Project settings** > **Cloud Messaging**. Under **Firebase Cloud Messaging
API (V1)** it should say **Enabled**. If it says Disabled, use its menu (⋮) to open it in Google
Cloud and click **Enable**. This is once for the whole project.

## 3. Make uwuHere's own service account key

The key comes from Google Cloud, where Firebase projects live. It belongs to uwuHere alone, so it
can be deleted without touching the other apps' keys.

1. Open <https://console.cloud.google.com/iam-admin/serviceaccounts>. At the top, pick the
   **UwU Apps** project.
2. Click **Create service account**:
   - **Service account name**: `uwuhere-push`
   - **Description**: `uwuHere's server, sending notifications through FCM`
   - Click **Create and continue**.
3. Under **Grant this service account access to project**, in **Select a role**, search for
   `Firebase Cloud Messaging API Admin` and pick it. Pick only this one. Click **Continue**, then
   **Done**.
4. In the list, click `uwuhere-push@…`, open the **Keys** tab, and click **Add key** > **Create
   new key** > **JSON** > **Create**. A `.json` file downloads.

> [!WARNING]
> That key is a password. Don't commit it, email it, or paste it anywhere but Vercel. FCM doesn't
> fence a key to one app, so a leaked key can push to every app in UwU Apps. If it ever leaks,
> delete it on the same **Keys** tab and make a new one.

## 4. Give the server its secrets (Vercel)

Open <https://vercel.com>, then the project that serves here.uwuapps.org, then **Settings** >
**Environment Variables**. Add each of these with **Production** ticked (and **Preview** if you
test there), and mark each **Sensitive** (`main-site/.env.example` lists them too):

| Key | Value |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | Open the key file from step 3 in Notepad and paste **everything** in it, from `{` to `}`. Base64 of the file works too |
| `GITHUB_WEBHOOK_SECRET` | A long random string. Make one in PowerShell with the command below, and keep it for step 5 |
| `GITHUB_TOKEN` (optional) | A GitHub fine-grained token with **Public repositories (read-only)** access and nothing else, from <https://github.com/settings/personal-access-tokens/new>. Without it, GitHub allows 60 release lookups an hour, which the site's 10-minute cache of the answer makes plenty |

```powershell
$b = New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { '{0:x2}' -f $_ })
```

Then redeploy so the functions see them: open **Deployments**, then the newest deployment's **⋯**
menu, then **Redeploy**. After that, delete the downloaded key file from your Downloads folder,
since Vercel has it now.

The server reads the key in `main-site/api/_lib/fcm.js`, signs its own short-lived token with it
(no Google library), and sends to the project the key names.

## 5. Tell GitHub to call the server when you publish a release (webhook)

1. Open <https://github.com/augy-studios/uwuHere/settings/hooks/new>.
2. Fill it in:
   - **Payload URL**: `https://here.uwuapps.org/api/push/release`
   - **Content type**: `application/json`. It has to be this one.
   - **Secret**: the same `GITHUB_WEBHOOK_SECRET` as in Vercel.
   - **Which events would you like to trigger this webhook?**: pick **Let me select individual
     events**, untick **Pushes**, and tick **Releases**.
   - **Active**: ticked.
3. Click **Add webhook**. GitHub sends a test ping straight away. Under **Recent Deliveries** it
   should show a green tick and the response `{"ok":true,"pong":true}`. A 401 response means the
   secret doesn't match Vercel's (or Vercel hasn't been redeployed since).

From now on, publishing an `android-v*` release with its APK attached pushes the notification
(`release/README.md`). Drafts, pre-releases and releases without an APK are skipped, and so is
re-publishing a version older than the newest. **Recent Deliveries** shows each answer, with the
reason when nothing was sent.

Attach the APK **before** clicking **Publish release**: the webhook is called the moment it's
published, and a release whose APK isn't there yet is skipped.

## 6. Build the app with Firebase in it

```powershell
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1
```

The build picks up `google-services.json` by itself (without it, the Gradle output says
`google-services.json not found: building without Firebase`). Install the new APK on your phone.
The App Bundle (`-Aab`) picks it up the same way.

## 7. Check it works

1. In the app, tap the bell in the Edge Tray and turn on all three switches. On Android 13 and
   later, Android asks to allow notifications: tap **Allow**. (No bell? The APK was built without
   `google-services.json`.)
2. **Check-ins**: on the phone, make an event with **Location** on, and keep its host page open
   for a moment (that's when the phone joins the event's topic). Close the app. From a second
   phone, open the event's link and check in by location. Within a few seconds the first phone
   shows "Name checked in by location. 1 checked in so far." Tapping it opens the host page.
3. **News**: send yourself a message from the console:
   1. In the UwU Apps project, open **Messaging** (in the left menu under **Run**, or search for
      it).
   2. Click **New campaign** > **Notifications**.
   3. Type a title and some text, then click **Next**.
   4. **Target**: pick **Topic** and type `uwuhere-news`. Use the topic, not the app: the topic
      reaches only people who turned news on. Click **Next**.
   5. **Scheduling**: **Now**. Then click **Next** until **Additional options**.
   6. **Additional options** > **Android notification channel**: `news`.
   7. Click **Review** > **Publish**.
   8. Lock your phone. It should arrive within a minute.
4. **New versions**: the same as news, with the topic `uwuhere-releases`, the channel `releases`,
   and under **Custom data** the key `type` with the value `release` (so a tap opens the Updates
   page). Or, once the webhook's set up, open it in GitHub, go to **Recent Deliveries**, and
   **Redeliver** a past `release` delivery whose action is `released`.

Sending news later works the same way as step 3: **Topic** `uwuhere-news`, channel `news`.

## Adding another UwU App later

The same steps in the same project: step 1 with that app's package name, and step 3 with a
service account of its own. Step 2 is done. Its topics get its own prefix.

## If something goes wrong

| What happens | What to do |
|---|---|
| The build stops with `No matching client found for package name 'org.uwuapps.here'` | `google-services.json` was downloaded before uwuHere was added. Download it again from **Project settings** > **Your apps** > **uwuHere**. |
| No bell in the Edge Tray, no **New versions of the app** in the Updates page | The APK was built without `google-services.json`. Check it's at `flutter\android\app\google-services.json`, then build again and reinstall. |
| "Notifications are off for uwuHere in Android's settings" | You said no to Android's prompt. Tap **Open Android's settings** under the switches, turn notifications on, and come back. |
| "Couldn't reach Firebase" when turning a switch on | The phone was offline, or has no Google Play services (some Huawei phones), which FCM needs. |
| No check-in notifications | Check `FIREBASE_SERVICE_ACCOUNT` is set and Vercel was redeployed, then look at the function logs for `/api/checkin`: a failed send logs `host alert not sent:` with FCM's answer. Same-wifi, tapped, Bluetooth and hotspot check-ins never notify, by design: they arrive on the host's open page. |
| Check-ins from an event made on another device don't notify | Open its host page on this phone once (with its password), so the phone joins its topic. |
| The test campaign never arrives | Check the topic is exactly `uwuhere-news` (or `uwuhere-releases`) and that switch is on. |
| The webhook shows `401 Bad signature` | The secret in GitHub and `GITHUB_WEBHOOK_SECRET` in Vercel differ, or Vercel wasn't redeployed after adding it. |
| The webhook shows `502` with `FIREBASE_SERVICE_ACCOUNT is not set` | Step 4 is missing or wasn't redeployed. |
| The webhook shows `502` with `FCM responded 403` | The service account is missing its role (step 3.3), or FCM's API is off (step 2). |
| The webhook shows `502` with `Google token responded 400: invalid_grant` | The key was deleted, or the server's clock is off. Make a new one (step 3.4), replace the variable, and redeploy. |
| The webhook shows `400 Not JSON` | The webhook's content type is `application/x-www-form-urlencoded`. Edit it to `application/json`. |
| The webhook shows `"sent":false` with `Not an android-v* release with its APK uploaded` | The tag doesn't start `android-v`, it's a pre-release, or the APK wasn't attached when you clicked **Publish**. Attach it, then **Redeliver** that delivery. |
