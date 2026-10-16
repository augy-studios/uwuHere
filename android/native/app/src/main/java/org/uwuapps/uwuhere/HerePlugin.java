/*
 * The app itself, to the page (main-site/js/app-bridge.js):
 *
 *   info()                    { version, versionCode, features, android }: what this app can do
 *   keepAwake({ on })         keeps the screen on, for a host's page waiting for same-wifi
 *                             check-ins. The page's own Screen Wake Lock does this in Chrome, but
 *                             Android's WebView has none
 *   brightness({ max })       the screen at full brightness while the big QR code is up, so the
 *                             back of a room can scan it, and back to the phone's own after
 *   saveFile({ name, text, mime })  the host's CSV, into Downloads (Android 10 and later) or
 *                             wherever you pick (Android 7 to 9). The WebView can't download a
 *                             file the page made itself. { saved, where }, where is "downloads"
 *                             or "picked"; saved is false if you backed out of picking
 *   update({ check, version })  the update window (UpdateActivity): check, the Edge Tray's
 *                             "Check for app updates", looks first and asks before downloading
 *   topics()                  { checkins, releases, news }: which notifications you've turned on
 *   setTopic({ topic, on })   turns "checkins", "releases" (new versions) or "news" on or off,
 *                             as FCM topic subscriptions, so the server needs no list of phones
 *   watchEvent({ topic, on }) an event this phone hosts, by its topic (uwuhere-host-<40 hex>,
 *                             main-site/js/app-notify.js), added to or taken off the events whose
 *                             check-ins come here while "checkins" is on
 *   openSettings({ what })    the app's notification settings ("notifications") or its page in
 *                             Android's settings ("app"), for location or notifications refused
 */
package org.uwuapps.uwuhere;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.provider.Settings;
import android.view.Window;
import android.view.WindowManager;

import androidx.activity.result.ActivityResult;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.android.gms.tasks.Task;
import com.google.android.gms.tasks.Tasks;
import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;

import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

@CapacitorPlugin(name = "Here")
public class HerePlugin extends Plugin {
    // FCM topics are shared by every app in the UwU Apps Firebase project, hence the prefix. The
    // server sends new versions to uwuhere-releases (main-site/api/push/release.js); news goes to
    // uwuhere-news from the Firebase console (android/FIREBASE-SETUP.md).
    private static final String TOPIC_PREFIX = "uwuhere-";
    // One per event, named from its host key, so only a phone holding the key can name it
    // (main-site/js/app-notify.js, main-site/api/_lib/alerts.js).
    private static final Pattern HOST_TOPIC = Pattern.compile("uwuhere-host-[0-9a-f]{40}");
    private static final String PREFS = "uwuhere";
    private static final String HOST_TOPICS = "host.topics";

    @PluginMethod
    public void info(PluginCall call) {
        JSObject out = new JSObject();
        try {
            PackageInfo info = getContext().getPackageManager().getPackageInfo(getContext().getPackageName(), 0);
            out.put("version", info.versionName);
            out.put("versionCode", Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? info.getLongVersionCode() : info.versionCode);
        } catch (PackageManager.NameNotFoundException e) {
            out.put("version", null);
        }
        JSArray features = new JSArray();
        features.put("keepawake");
        features.put("brightness");
        features.put("savefile");
        features.put("settings");
        features.put("update"); // UpdateActivity, for the update bar
        features.put("checkupdate"); // UpdateActivity's check, for the Edge Tray
        // Firebase is set up for this build (google-services.json): notifications can come.
        if (firebaseReady()) features.put("push");
        out.put("features", features);
        out.put("android", Build.VERSION.SDK_INT);
        call.resolve(out);
    }

    @PluginMethod
    public void keepAwake(PluginCall call) {
        boolean on = Boolean.TRUE.equals(call.getBoolean("on", false));
        Activity activity = getActivity();
        activity.runOnUiThread(() -> {
            Window window = activity.getWindow();
            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            call.resolve();
        });
    }

    // For this app's window only: the phone's own setting is untouched, and Android puts it back
    // by itself whenever the app isn't on screen.
    @PluginMethod
    public void brightness(PluginCall call) {
        boolean max = Boolean.TRUE.equals(call.getBoolean("max", false));
        Activity activity = getActivity();
        activity.runOnUiThread(() -> {
            Window window = activity.getWindow();
            WindowManager.LayoutParams attrs = window.getAttributes();
            attrs.screenBrightness = max ? WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
                    : WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE;
            window.setAttributes(attrs);
            call.resolve();
        });
    }

    @PluginMethod
    public void saveFile(PluginCall call) {
        String name = call.getString("name", "");
        String text = call.getString("text");
        String mime = call.getString("mime", "text/plain");
        // Only a plain file name: nothing that walks out of Downloads.
        if (text == null || name.isEmpty() || name.length() > 120 || !name.matches("[\\w .()-]+")) {
            call.reject("That file can't be saved.");
            return;
        }

        // Android 10 and later: straight into Downloads, which needs no permission.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentResolver resolver = getContext().getContentResolver();
            ContentValues values = new ContentValues();
            values.put(MediaStore.Downloads.DISPLAY_NAME, name);
            values.put(MediaStore.Downloads.MIME_TYPE, mime);
            values.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
            values.put(MediaStore.Downloads.IS_PENDING, 1);
            Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) {
                call.reject("Couldn't save to Downloads. Is the phone full?");
                return;
            }
            try {
                write(uri, text);
                values.clear();
                values.put(MediaStore.Downloads.IS_PENDING, 0);
                resolver.update(uri, values, null, null);
            } catch (IOException e) {
                resolver.delete(uri, null, null);
                call.reject("Couldn't save to Downloads. Is the phone full?");
                return;
            }
            JSObject out = new JSObject();
            out.put("saved", true);
            out.put("where", "downloads");
            call.resolve(out);
            return;
        }

        // Android 7 to 9 would need the storage permission for Downloads, so Android's own
        // "save as" screen picks the place instead, which needs none.
        Intent pick = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(mime)
                .putExtra(Intent.EXTRA_TITLE, name);
        startActivityForResult(call, pick, "fileSaveResult");
    }

    @ActivityCallback
    private void fileSaveResult(PluginCall call, ActivityResult result) {
        if (call == null) return;
        JSObject out = new JSObject();
        Uri uri = result.getData() == null ? null : result.getData().getData();
        if (result.getResultCode() != Activity.RESULT_OK || uri == null) {
            out.put("saved", false);
            call.resolve(out);
            return;
        }
        try {
            write(uri, call.getString("text", ""));
        } catch (IOException e) {
            call.reject("Couldn't save the file there. Try another place.");
            return;
        }
        out.put("saved", true);
        out.put("where", "picked");
        call.resolve(out);
    }

    private void write(Uri uri, String text) throws IOException {
        try (OutputStream out = getContext().getContentResolver().openOutputStream(uri, "w")) {
            if (out == null) throw new IOException("No stream for " + uri);
            out.write(text.getBytes(StandardCharsets.UTF_8));
        }
    }

    @PluginMethod
    public void update(PluginCall call) {
        UpdateActivity.start(getActivity(), Boolean.TRUE.equals(call.getBoolean("check", false)), call.getString("version"));
        call.resolve();
    }

    @PluginMethod
    public void topics(PluginCall call) {
        SharedPreferences prefs = prefs();
        JSObject out = new JSObject();
        out.put("checkins", prefs.getBoolean("topic.checkins", false));
        out.put("releases", prefs.getBoolean("topic.releases", false));
        out.put("news", prefs.getBoolean("topic.news", false));
        call.resolve(out);
    }

    @PluginMethod
    public void setTopic(PluginCall call) {
        String topic = call.getString("topic", "");
        boolean on = Boolean.TRUE.equals(call.getBoolean("on", false));
        if (!"checkins".equals(topic) && !"releases".equals(topic) && !"news".equals(topic)) {
            call.reject("Unknown topic");
            return;
        }
        if (!firebaseReady()) {
            call.reject("This copy of the app can't get notifications yet.");
            return;
        }

        // Check-ins aren't one topic but one per event this phone hosts (watchEvent).
        List<String> names = new ArrayList<>();
        if ("checkins".equals(topic)) names.addAll(hostTopics());
        else names.add(TOPIC_PREFIX + topic);

        subscribe(names, on).addOnCompleteListener(task -> {
            if (!task.isSuccessful()) {
                call.reject("Couldn't reach Firebase. Check you're online, then try again.");
                return;
            }
            prefs().edit().putBoolean("topic." + topic, on).apply();
            JSObject out = new JSObject();
            out.put("topic", topic);
            out.put("on", on);
            call.resolve(out);
        });
    }

    @PluginMethod
    public void watchEvent(PluginCall call) {
        String topic = call.getString("topic", "");
        boolean on = Boolean.TRUE.equals(call.getBoolean("on", false));
        if (!HOST_TOPIC.matcher(topic).matches()) {
            call.reject("Not an event's topic");
            return;
        }

        Set<String> topics = hostTopics();
        boolean changed = on ? topics.add(topic) : topics.remove(topic);
        if (changed) prefs().edit().putStringSet(HOST_TOPICS, topics).apply();

        // Joined now only while check-ins are on; setTopic joins the rest when they're turned on.
        // Left whatever the switch says, as the switch may have been on when it was joined.
        boolean alerts = prefs().getBoolean("topic.checkins", false);
        if (!firebaseReady() || (on && !alerts)) {
            call.resolve();
            return;
        }
        List<String> one = new ArrayList<>();
        one.add(topic);
        // Not waited for: the page carries on either way, and a phone offline now joins the next
        // time the host page opens, as it asks again then.
        subscribe(one, on);
        call.resolve();
    }

    private Task<Void> subscribe(List<String> names, boolean on) {
        FirebaseMessaging messaging = FirebaseMessaging.getInstance();
        messaging.setAutoInitEnabled(true);
        List<Task<Void>> tasks = new ArrayList<>();
        for (String name : names) {
            tasks.add(on ? messaging.subscribeToTopic(name) : messaging.unsubscribeFromTopic(name));
        }
        return Tasks.whenAll(tasks);
    }

    // A copy: the set SharedPreferences hands out mustn't be changed in place.
    private Set<String> hostTopics() {
        return new HashSet<>(prefs().getStringSet(HOST_TOPICS, new HashSet<>()));
    }

    @PluginMethod
    public void openSettings(PluginCall call) {
        String pkg = getContext().getPackageName();
        Intent intent;
        if ("notifications".equals(call.getString("what")) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg);
        } else {
            intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", pkg, null));
        }
        try {
            getActivity().startActivity(intent);
        } catch (ActivityNotFoundException e) {
            getActivity().startActivity(new Intent(Settings.ACTION_SETTINGS));
        }
        call.resolve();
    }

    private SharedPreferences prefs() {
        return getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    // Built with google-services.json, which starts Firebase as the app starts. Without it there
    // is no Firebase, and FirebaseMessaging would throw.
    private boolean firebaseReady() {
        return !FirebaseApp.getApps(getContext()).isEmpty();
    }
}
