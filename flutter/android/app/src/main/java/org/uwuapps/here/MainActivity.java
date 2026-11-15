package org.uwuapps.here;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.net.Uri;
import android.nfc.NfcAdapter;
import android.nfc.cardemulation.CardEmulation;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.provider.Settings;
import android.view.WindowManager;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.FileProvider;
import androidx.core.location.LocationManagerCompat;

import com.google.android.gms.tasks.Task;
import com.google.android.gms.tasks.Tasks;
import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * The app's one window, and the bridge to the Dart side (lib/native/bridge.dart): one method
 * channel, whose "call" names a plugin and a method and carries its options as JSON, answered with
 * JSON. Every option from the Dart side is checked here, as the Capacitor app's HerePlugin checked
 * the page's. Two plugins:
 *
 *   App   info (version, features), launchLink, installApk (the GitHub APK only), setReleases,
 *         openSettings, background (Back's second press), and migrate (what the Capacitor app's
 *         WebView kept for the site, read once)
 *   Here  what only the phone can do for an event, ported from the Capacitor app's HerePlugin:
 *         brightness({ max })          this window at full brightness while a QR code is up
 *         saveFile({ name, text, mime })  the CSV into Downloads (10+) or where you pick (7 to 9)
 *         topics(), setTopic({ topic, on })  checkins, releases, news: FCM topics, so the server
 *                                      keeps no list of phones
 *         watchEvent({ topic, on })    an event this phone hosts, by its topic (uwuhere-host-<40 hex>)
 *         openSettings({ what })       notifications, nfc, bluetooth, or the app's page
 *         tap({ on, code, hostKey })   tapping phones: this phone answers as an NFC tag (TapService)
 *         hotspot({ on, … }), hotspotAnswer  checking in with no internet (Hotspot, LocalServer)
 *         bluetooth({ on, code, ask }), meshAnswer, meshCheckIn  Bluetooth, app to app (Mesh)
 *         widget({ … })                the "Your event" home screen widget (WidgetData)
 *
 * And their events: App's "link" (a link, a tag or a tapped notification arriving while the app
 * runs) and "openUpdates"; Here's "tapped", "hotspotCheckin", "hotspotStopped" and "meshCheckin".
 */
public class MainActivity extends FlutterActivity {
    static final String CHANNEL = "org.uwuapps.here/bridge";
    static final String SITE = "https://here.uwuapps.org";
    static final String HOST = "here.uwuapps.org";
    static final String OPEN_UPDATES = "org.uwuapps.here.OPEN_UPDATES";

    // FCM topics are shared by every app in the UwU Apps Firebase project, hence the prefix. The
    // server sends new versions to uwuhere-releases (main-site/api/push/release.js); news goes to
    // uwuhere-news from the Firebase console.
    private static final String TOPIC_PREFIX = "uwuhere-";
    private static final Pattern HOST_TOPIC = Pattern.compile("uwuhere-host-[0-9a-f]{40}");
    private static final String PREFS = "uwuhere";
    private static final String HOST_TOPICS = "host.topics";
    static final Pattern EVENT_CODE = Pattern.compile("[BCDFGHJKLMNPQRSTVWXYZ2-9]{6}");
    static final Pattern HOST_KEY = Pattern.compile("[A-Za-z0-9_-]{43}");

    private static final int SAVE_FILE = 51;

    private MethodChannel channel;
    private String launchLink;
    private final Set<String> listening = new HashSet<>();

    private Hotspot hotspot;
    private Mesh mesh;

    // A permission prompt waiting for its answer, and a "save as" waiting for its place.
    private int nextAsk = 100;
    private final Map<Integer, Runnable[]> asking = new HashMap<>();
    private MethodChannel.Result pendingSave;
    private String pendingSaveText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Notifications.createChannels(this);
        launchLink = linkOf(getIntent());
        // Into the camera cutout, rather than a black strip beside it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            getWindow().getAttributes().layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
        // Left on by an app that was closed mid-event: nobody is hosting now.
        TapService.stop(this);
        TapService.listener = () -> emit("Here", "tapped", new HashMap<>());
        hotspot = new Hotspot(this, new Hotspot.Listener() {
            @Override
            public boolean checkIn(String id, String name, String note, String deviceHash) {
                if (!listening.contains("Here.hotspotCheckin")) return false;
                emit("Here", "hotspotCheckin", checkin(id, name, note, deviceHash));
                return true;
            }

            @Override
            public void stopped() {
                emit("Here", "hotspotStopped", new HashMap<>());
            }
        });
        if (Mesh.available(this)) mesh = new Mesh(this);
    }

    @Override
    protected void onDestroy() {
        if (hotspot != null) hotspot.stop();
        if (mesh != null) mesh.stopAdvertising();
        TapService.stop(this);
        super.onDestroy();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (TapService.active()) preferTapService(true);
    }

    @Override
    protected void onPause() {
        if (TapService.active()) preferTapService(false);
        super.onPause();
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this::onCall);
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String link = linkOf(intent);
        if (link == null) return;
        Map<String, Object> data = new HashMap<>();
        data.put("url", link);
        emit("App", "link", data);
    }

    /**
     * The app's own address for what an intent asks: one of the site's links (a scanned QR code, a
     * tag from a host's phone, a widget), a uwu://here/ link, or a tapped notification: "Alex
     * checked in" opens that event's host page, "Version x.y.z is out" the Updates page.
     */
    private static String linkOf(Intent intent) {
        if (intent == null) return null;
        if (OPEN_UPDATES.equals(intent.getAction())) return "uwu://here/updates";
        String type = intent.getStringExtra("type");
        if ("release".equals(type) || "update".equals(type)) {
            intent.removeExtra("type");
            return "uwu://here/updates";
        }
        if ("checkin".equals(type)) {
            String code = intent.getStringExtra("code");
            intent.removeExtra("type");
            return code != null && EVENT_CODE.matcher(code).matches() ? "uwu://here/host?id=" + code : null;
        }
        Uri data = intent.getData();
        String action = intent.getAction();
        if (data == null) return null;
        if (!Intent.ACTION_VIEW.equals(action) && !"android.nfc.action.NDEF_DISCOVERED".equals(action)) return null;
        if ("https".equals(data.getScheme()) && HOST.equalsIgnoreCase(data.getHost())) return data.toString();
        if ("uwu".equals(data.getScheme()) && "here".equalsIgnoreCase(data.getHost())) return data.toString();
        return null;
    }

    private void emit(String plugin, String event, Map<String, Object> data) {
        Map<String, Object> args = new HashMap<>();
        args.put("plugin", plugin);
        args.put("event", event);
        args.put("data", new JSONObject(data).toString());
        new Handler(Looper.getMainLooper()).post(() -> {
            if (channel != null) channel.invokeMethod("event", args);
        });
    }

    private static Map<String, Object> checkin(String id, String name, String note, String deviceHash) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("name", name);
        m.put("note", note);
        m.put("deviceHash", deviceHash);
        return m;
    }

    private void onCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "hello":
                result.success(null);
                return;
            case "listen":
            case "unlisten": {
                String key = call.argument("plugin") + "." + call.argument("event");
                if ("listen".equals(call.method)) listening.add(key);
                else listening.remove(key);
                result.success(null);
                return;
            }
            case "call":
                break;
            default:
                result.notImplemented();
                return;
        }
        String plugin = call.argument("plugin");
        String method = call.argument("method");
        JSONObject options;
        try {
            String raw = call.argument("options");
            options = new JSONObject(raw == null ? "{}" : raw);
        } catch (Exception e) {
            options = new JSONObject();
        }
        try {
            if ("App".equals(plugin)) app(method, options, result);
            else if ("Here".equals(plugin)) here(method, options, result);
            else result.error("unavailable", "No plugin " + plugin, null);
        } catch (Exception e) {
            result.error("failed", e.getMessage(), null);
        }
    }

    private static void ok(MethodChannel.Result result, JSONObject answer) {
        result.success(answer == null ? null : answer.toString());
    }

    private static JSONObject obj(Object... kv) {
        JSONObject o = new JSONObject();
        try {
            for (int i = 0; i + 1 < kv.length; i += 2) o.put((String) kv[i], kv[i + 1] == null ? JSONObject.NULL : kv[i + 1]);
        } catch (JSONException ignored) {
            // Keys are strings; nothing to go wrong.
        }
        return o;
    }

    private boolean firebaseReady() {
        try {
            return !FirebaseApp.getApps(this).isEmpty();
        } catch (Throwable t) {
            return false;
        }
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    // ---------- permissions ----------

    private boolean granted(String[] permissions) {
        for (String p : permissions) {
            if (checkSelfPermission(p) != PackageManager.PERMISSION_GRANTED) return false;
        }
        return true;
    }

    /** Asks for what's not granted yet, then runs one of the two. */
    private void ask(String[] permissions, Runnable yes, Runnable no) {
        if (granted(permissions)) {
            yes.run();
            return;
        }
        int code = nextAsk++;
        asking.put(code, new Runnable[] {yes, no});
        requestPermissions(permissions, code);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grants) {
        super.onRequestPermissionsResult(requestCode, permissions, grants);
        Runnable[] then = asking.remove(requestCode);
        if (then == null) return;
        if (granted(permissions)) then[0].run();
        else then[1].run();
    }

    // ---------- App ----------

    private void app(String method, JSONObject o, MethodChannel.Result result) throws Exception {
        switch (method) {
            case "info": {
                JSONArray features = new JSONArray();
                features.put("links");
                features.put("brightness");
                features.put("savefile");
                features.put("settings");
                features.put("tap"); // TapService; tap() says if this phone has no NFC
                if (Hotspot.supported()) features.put("hotspot");
                if (mesh != null) features.put("mesh"); // Bluetooth, app to app, with Play services
                features.put("widget");
                if (!BuildConfig.PLAY) {
                    features.put("update");
                    features.put("checkupdate");
                }
                // Only with google-services.json built in: without it nothing could ever arrive.
                if (firebaseReady()) features.put("push");
                JSONObject a = new JSONObject();
                a.put("platform", "android");
                a.put("version", BuildConfig.VERSION_NAME);
                a.put("build", BuildConfig.VERSION_CODE);
                a.put("play", BuildConfig.PLAY);
                a.put("sdk", Build.VERSION.SDK_INT);
                // For a bug report (lib/features/bug/bug_report.dart): "Android 16 · Google Pixel 9".
                a.put("release", Build.VERSION.RELEASE);
                a.put("model", (Build.MANUFACTURER + " " + Build.MODEL).trim());
                a.put("features", features);
                ok(result, a);
                return;
            }
            case "launchLink": {
                JSONObject a = new JSONObject();
                if (launchLink != null) a.put("url", launchLink);
                launchLink = null;
                ok(result, a);
                return;
            }
            case "installApk":
                installApk(o, result);
                return;
            case "setReleases":
                setTopic("releases", o.optBoolean("on"), result);
                return;
            case "openSettings":
                openSettings(o.optString("page", "app"));
                ok(result, null);
                return;
            case "background":
                moveTaskToBack(true);
                ok(result, new JSONObject());
                return;
            case "migrate":
                migrate(result);
                return;
            default:
                result.error("unavailable", "No method " + method, null);
        }
    }

    private void openSettings(String what) {
        String pkg = getPackageName();
        Intent intent;
        if ("notifications".equals(what) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg);
        } else if ("nfc".equals(what)) {
            intent = new Intent(Settings.ACTION_NFC_SETTINGS);
        } else if ("bluetooth".equals(what)) {
            intent = new Intent(Settings.ACTION_BLUETOOTH_SETTINGS);
        } else if ("location".equals(what)) {
            intent = new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS);
        } else {
            intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", pkg, null));
        }
        try {
            startActivity(intent);
        } catch (ActivityNotFoundException e) {
            startActivity(new Intent(Settings.ACTION_SETTINGS));
        }
    }

    /** A downloaded, checked APK to Android's installer, once installing from this app is allowed. */
    private void installApk(JSONObject o, MethodChannel.Result result) {
        if (BuildConfig.PLAY) {
            result.error("unavailable", "Google Play updates this app", null);
            return;
        }
        File apk = new File(o.optString("path"));
        if (!apk.exists()) {
            result.error("failed", "The download is gone", null);
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !getPackageManager().canRequestPackageInstalls()) {
            startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + getPackageName())));
            result.error("permission", "Allow installing apps from uwuHere", null);
            return;
        }
        Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".files", apk);
        Intent i = new Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(i);
        ok(result, null);
    }

    private static final String DUMP = "(function(){var o={};try{for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);o[k]=localStorage.getItem(k);}}catch(e){}return JSON.stringify(o);})()";

    /**
     * What the Capacitor app (1.0.x) kept in its WebView's localStorage for the site: the events
     * this phone hosts and their host keys, check-ins, the name last typed, the theme. Read by a
     * WebView that's never shown, given the site's address as its own so it sees the site's
     * storage, with nothing fetched. The WebView's copy is left as it was.
     */
    @SuppressLint("SetJavaScriptEnabled")
    private void migrate(MethodChannel.Result result) {
        WebView web;
        try {
            web = new WebView(this);
        } catch (RuntimeException e) {
            // No WebView on this phone at all: nothing to read.
            ok(result, obj("found", false, "items", new JSONObject()));
            return;
        }
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.setWebViewClient(new WebViewClient() {
            private boolean done;

            @Override
            public void onPageFinished(WebView view, String url) {
                if (done) return;
                done = true;
                view.evaluateJavascript(DUMP, value -> {
                    JSONObject out = new JSONObject();
                    JSONObject items = new JSONObject();
                    try {
                        // evaluateJavascript hands back the result as a JSON string literal.
                        Object text = new JSONTokener(value == null ? "\"{}\"" : value).nextValue();
                        JSONObject all = new JSONObject(text instanceof String ? (String) text : "{}");
                        for (Iterator<String> keys = all.keys(); keys.hasNext(); ) {
                            String k = keys.next();
                            items.put(k, all.optString(k));
                        }
                        out.put("found", items.length() > 0);
                        out.put("items", items);
                    } catch (JSONException ignored) {
                        // Nothing readable: nothing to bring over.
                    }
                    ok(result, out);
                    view.destroy();
                });
            }
        });
        web.loadDataWithBaseURL(SITE + "/", "<!doctype html><title></title>", "text/html", "utf-8", null);
    }

    // ---------- Here ----------

    private void here(String method, JSONObject o, MethodChannel.Result result) throws Exception {
        switch (method) {
            case "brightness": {
                // For this app's window only: the phone's own setting is untouched, and Android
                // puts it back by itself whenever the app isn't on screen.
                boolean max = o.optBoolean("max");
                WindowManager.LayoutParams attrs = getWindow().getAttributes();
                attrs.screenBrightness = max ? WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
                        : WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE;
                getWindow().setAttributes(attrs);
                ok(result, null);
                return;
            }
            case "saveFile":
                saveFile(o, result);
                return;
            case "topics": {
                SharedPreferences p = prefs();
                boolean allowed = Build.VERSION.SDK_INT < 33
                        ? NotificationManagerCompat.from(this).areNotificationsEnabled()
                        : checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
                ok(result, obj(
                        "checkins", p.getBoolean("topic.checkins", false),
                        "releases", p.getBoolean("topic.releases", false),
                        "news", p.getBoolean("topic.news", false),
                        "permission", allowed ? "granted" : "denied"));
                return;
            }
            case "setTopic":
                setTopic(o.optString("topic"), o.optBoolean("on"), result);
                return;
            case "watchEvent":
                watchEvent(o, result);
                return;
            case "openSettings":
                openSettings(o.optString("what", "app"));
                ok(result, null);
                return;
            case "tap":
                tap(o, result);
                return;
            case "hotspot":
                hotspot(o, result);
                return;
            case "hotspotAnswer":
                hotspot.answer(o.optString("id"), o.optBoolean("ok"), str(o, "at"), str(o, "message"));
                ok(result, null);
                return;
            case "bluetooth":
                bluetooth(o, result);
                return;
            case "meshAnswer":
                if (mesh != null) mesh.answer(o.optString("id"), o.optBoolean("ok"), str(o, "at"), str(o, "message"));
                ok(result, null);
                return;
            case "meshCheckIn":
                meshCheckIn(o, result);
                return;
            case "widget":
                widget(o, result);
                return;
            default:
                result.error("unavailable", "No method " + method, null);
        }
    }

    /** A string option, or null when it's missing or JSON null. */
    private static String str(JSONObject o, String key) {
        return o.isNull(key) ? null : o.optString(key, null);
    }

    // ---- the CSV ----

    private void saveFile(JSONObject o, MethodChannel.Result result) {
        String name = o.optString("name", "");
        String text = str(o, "text");
        String mime = o.optString("mime", "text/plain");
        // Only a plain file name: nothing that walks out of Downloads.
        if (text == null || name.isEmpty() || name.length() > 120 || !name.matches("[\\w .()-]+")) {
            result.error("failed", "That file can't be saved.", null);
            return;
        }
        // Android 10 and later: straight into Downloads, which needs no permission.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentResolver resolver = getContentResolver();
            ContentValues values = new ContentValues();
            values.put(MediaStore.Downloads.DISPLAY_NAME, name);
            values.put(MediaStore.Downloads.MIME_TYPE, mime);
            values.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
            values.put(MediaStore.Downloads.IS_PENDING, 1);
            Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) {
                result.error("failed", "Couldn't save to Downloads. Is the phone full?", null);
                return;
            }
            try {
                write(uri, text);
                values.clear();
                values.put(MediaStore.Downloads.IS_PENDING, 0);
                resolver.update(uri, values, null, null);
            } catch (IOException e) {
                resolver.delete(uri, null, null);
                result.error("failed", "Couldn't save to Downloads. Is the phone full?", null);
                return;
            }
            ok(result, obj("saved", true, "where", "downloads"));
            return;
        }
        // Android 7 to 9 would need the storage permission for Downloads, so Android's own "save
        // as" screen picks the place instead, which needs none.
        if (pendingSave != null) pendingSave.error("cancelled", "Another save started", null);
        pendingSave = result;
        pendingSaveText = text;
        Intent pick = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(mime)
                .putExtra(Intent.EXTRA_TITLE, name);
        startActivityForResult(pick, SAVE_FILE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != SAVE_FILE || pendingSave == null) return;
        MethodChannel.Result result = pendingSave;
        String text = pendingSaveText;
        pendingSave = null;
        pendingSaveText = null;
        Uri uri = data == null ? null : data.getData();
        if (resultCode != Activity.RESULT_OK || uri == null) {
            ok(result, obj("saved", false));
            return;
        }
        try {
            write(uri, text == null ? "" : text);
        } catch (IOException e) {
            result.error("failed", "Couldn't save the file there. Try another place.", null);
            return;
        }
        ok(result, obj("saved", true, "where", "picked"));
    }

    private void write(Uri uri, String text) throws IOException {
        try (OutputStream out = getContentResolver().openOutputStream(uri, "w")) {
            if (out == null) throw new IOException("No stream for " + uri);
            out.write(text.getBytes(StandardCharsets.UTF_8));
        }
    }

    // ---- notifications ----

    /** Turns "checkins", "releases" or "news" on or off, asking for notifications first (13+). */
    private void setTopic(String topic, boolean on, MethodChannel.Result result) {
        if (!"checkins".equals(topic) && !"releases".equals(topic) && !"news".equals(topic)) {
            result.error("failed", "Unknown topic", null);
            return;
        }
        if (!firebaseReady()) {
            result.error("unavailable", "This copy of the app can't get notifications.", null);
            return;
        }
        Runnable go = () -> {
            // Check-ins aren't one topic but one per event this phone hosts (watchEvent).
            List<String> names = new ArrayList<>();
            if ("checkins".equals(topic)) names.addAll(hostTopics());
            else names.add(TOPIC_PREFIX + topic);
            subscribe(names, on).addOnCompleteListener(task -> {
                if (!task.isSuccessful()) {
                    result.error("network", "Couldn't reach Firebase. Check you're online, then try again.", null);
                    return;
                }
                prefs().edit().putBoolean("topic." + topic, on).apply();
                ok(result, obj("topic", topic, "on", on));
            });
        };
        if (on && Build.VERSION.SDK_INT >= 33) {
            ask(new String[] {Manifest.permission.POST_NOTIFICATIONS}, go,
                    () -> result.error("permission", "Notifications are off for uwuHere", null));
        } else {
            go.run();
        }
    }

    private void watchEvent(JSONObject o, MethodChannel.Result result) {
        String topic = o.optString("topic", "");
        boolean on = o.optBoolean("on");
        if (!HOST_TOPIC.matcher(topic).matches()) {
            result.error("failed", "Not an event's topic", null);
            return;
        }
        Set<String> topics = hostTopics();
        boolean changed = on ? topics.add(topic) : topics.remove(topic);
        if (changed) prefs().edit().putStringSet(HOST_TOPICS, topics).apply();
        // Joined now only while check-ins are on; setTopic joins the rest when they're turned on.
        // Left whatever the switch says, as the switch may have been on when it was joined.
        boolean alerts = prefs().getBoolean("topic.checkins", false);
        if (firebaseReady() && (!on || alerts)) {
            List<String> one = new ArrayList<>();
            one.add(topic);
            // Not waited for: a phone offline now joins the next time the host page opens.
            subscribe(one, on);
        }
        ok(result, null);
    }

    private Task<Void> subscribe(List<String> names, boolean on) {
        FirebaseMessaging messaging = FirebaseMessaging.getInstance();
        messaging.setAutoInitEnabled(true);
        List<Task<Void>> tasks = new ArrayList<>();
        for (String name : names) tasks.add(on ? messaging.subscribeToTopic(name) : messaging.unsubscribeFromTopic(name));
        return Tasks.whenAll(tasks);
    }

    // A copy: the set SharedPreferences hands out mustn't be changed in place.
    private Set<String> hostTopics() {
        return new HashSet<>(prefs().getStringSet(HOST_TOPICS, new HashSet<>()));
    }

    // ---- tapping phones ----

    private void tap(JSONObject o, MethodChannel.Result result) {
        if (!o.optBoolean("on")) {
            TapService.stop(this);
            preferTapService(false);
            ok(result, obj("state", "idle"));
            return;
        }
        if (!TapService.supported(this)) {
            ok(result, obj("state", "unsupported"));
            return;
        }
        String code = o.optString("code", "");
        String hostKey = o.optString("hostKey", "");
        if (!EVENT_CODE.matcher(code).matches() || !HOST_KEY.matcher(hostKey).matches()) {
            result.error("failed", "Not an event this phone hosts", null);
            return;
        }
        TapService.start(this, code, hostKey);
        preferTapService(true);
        NfcAdapter nfc = NfcAdapter.getDefaultAdapter(this);
        ok(result, obj("state", nfc != null && nfc.isEnabled() ? "ready" : "nfc-off"));
    }

    // While the host page is in front, taps come here even if another app on this phone also
    // answers as a tag. Android only takes this from the app on screen, so it's said again each
    // time the app comes back.
    private void preferTapService(boolean on) {
        NfcAdapter nfc = NfcAdapter.getDefaultAdapter(this);
        if (nfc == null) return;
        runOnUiThread(() -> {
            try {
                CardEmulation cards = CardEmulation.getInstance(nfc);
                if (on) cards.setPreferredService(this, new ComponentName(this, TapService.class));
                else cards.unsetPreferredService(this);
            } catch (RuntimeException e) {
                // Not in front just now, or a phone without card emulation.
            }
        });
    }

    // ---- the hotspot ----

    private static String hotspotPermission() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ? Manifest.permission.NEARBY_WIFI_DEVICES : Manifest.permission.ACCESS_FINE_LOCATION;
    }

    private void hotspot(JSONObject o, MethodChannel.Result result) {
        if (!o.optBoolean("on")) {
            hotspot.stop();
            ok(result, obj("state", "off"));
            return;
        }
        if (!Hotspot.supported()) {
            ok(result, obj("state", "unsupported", "message", "This phone's Android is too old to make a hotspot."));
            return;
        }
        if (!EVENT_CODE.matcher(o.optString("code", "")).matches()) {
            result.error("failed", "Not an event this phone hosts", null);
            return;
        }
        ask(new String[] {hotspotPermission()}, () -> startHotspot(o, result), () -> ok(result, obj("state", "denied", "message",
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                        ? "uwuHere needs \"Nearby devices\" to make a hotspot. Allow it in the app's settings."
                        : "uwuHere needs location to make a hotspot. Allow it in the app's settings.")));
    }

    private boolean locationOn() {
        LocationManager lm = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        return lm != null && LocationManagerCompat.isLocationEnabled(lm);
    }

    private void startHotspot(JSONObject o, MethodChannel.Result result) {
        // Before Android 13 a hotspot also needs location switched on, not just allowed.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && !locationOn()) {
            ok(result, obj("state", "location-off", "message", "Turn on location in this phone's settings, then try again."));
            return;
        }
        JSONObject event = new JSONObject();
        try {
            event.put("code", o.getString("code"));
            event.put("title", o.optString("title", ""));
            event.put("buttonLabel", o.optString("buttonLabel", "I'm here"));
            String colour = o.optString("buttonColor", "#ccffcc");
            event.put("buttonColor", colour.matches("#[0-9a-fA-F]{6}") ? colour : "#ccffcc");
            String noteLabel = str(o, "noteLabel");
            event.put("noteLabel", noteLabel == null || noteLabel.isEmpty() ? JSONObject.NULL : noteLabel);
        } catch (JSONException e) {
            result.error("failed", "That event couldn't be read", null);
            return;
        }
        runOnUiThread(() -> hotspot.start(event, new Hotspot.Started() {
            @Override
            public void started(String ssid, String password, String security, String url) {
                ok(result, obj("state", "on", "ssid", ssid, "password", password, "security", security, "url", url));
            }

            @Override
            public void failed(String state, String message) {
                ok(result, obj("state", state, "message", message));
            }
        }));
    }

    // ---- Bluetooth, app to app (Mesh) ----

    /** What Nearby Connections needs, by Android version. */
    private static String[] meshPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return new String[] {Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE,
                    Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.NEARBY_WIFI_DEVICES};
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return new String[] {Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE,
                    Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION};
        }
        return new String[] {Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION};
    }

    private boolean bluetoothOn() {
        BluetoothManager bm = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        BluetoothAdapter adapter = bm == null ? null : bm.getAdapter();
        return adapter != null && adapter.isEnabled();
    }

    /** Host: advertise this event, or stop. Without `ask` it never prompts by itself. */
    private void bluetooth(JSONObject o, MethodChannel.Result result) {
        if (!o.optBoolean("on")) {
            if (mesh != null) mesh.stopAdvertising();
            ok(result, obj("state", "idle"));
            return;
        }
        if (mesh == null) {
            ok(result, obj("state", "unsupported"));
            return;
        }
        String code = o.optString("code", "");
        if (!EVENT_CODE.matcher(code).matches()) {
            result.error("failed", "Not an event this phone hosts", null);
            return;
        }
        if (!granted(meshPermissions())) {
            if (o.optBoolean("ask")) {
                ask(meshPermissions(), () -> startAdvertising(code, result), () -> ok(result, obj("state", "denied")));
            } else {
                ok(result, obj("state", "needs-permission"));
            }
            return;
        }
        startAdvertising(code, result);
    }

    private void startAdvertising(String code, MethodChannel.Result result) {
        if (!bluetoothOn()) {
            ok(result, obj("state", "bt-off"));
            return;
        }
        mesh.advertise(code, (id, name, note, deviceHash) -> {
            if (!listening.contains("Here.meshCheckin")) return false;
            emit("Here", "meshCheckin", checkin(id, name, note, deviceHash));
            return true;
        }, new Mesh.Started() {
            @Override
            public void started() {
                ok(result, obj("state", "ready"));
            }

            @Override
            public void failed(String message) {
                ok(result, obj("state", "failed", "message", message));
            }
        });
    }

    /** Attendee: { ok, at } or { ok: false, reason, message }. Asks the first time. */
    private void meshCheckIn(JSONObject o, MethodChannel.Result result) {
        if (mesh == null) {
            ok(result, obj("ok", false, "reason", "unsupported", "message", "This phone has no Google Play services, which Bluetooth check-in needs."));
            return;
        }
        String code = o.optString("code", "");
        if (!EVENT_CODE.matcher(code).matches()) {
            result.error("failed", "Not an event code", null);
            return;
        }
        ask(meshPermissions(), () -> meshCheckInAllowed(code, o, result), () -> ok(result, obj("ok", false, "reason", "denied",
                "message", "uwuHere needs \"Nearby devices\" to check in by Bluetooth. Allow it in the app's settings.")));
    }

    private void meshCheckInAllowed(String code, JSONObject o, MethodChannel.Result result) {
        if (!bluetoothOn()) {
            ok(result, obj("ok", false, "reason", "bt-off", "message", "Turn on Bluetooth to check in phone to phone."));
            return;
        }
        // Before Android 12, looking for Bluetooth devices also needs location switched on.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && !locationOn()) {
            ok(result, obj("ok", false, "reason", "location-off", "message", "Turn on location in this phone's settings to check in by Bluetooth."));
            return;
        }
        JSONObject message = new JSONObject();
        try {
            message.put("v", 1);
            message.put("type", "checkin");
            message.put("code", code);
            message.put("name", o.optString("name", ""));
            String note = str(o, "note");
            message.put("note", note == null || note.isEmpty() ? JSONObject.NULL : note);
            message.put("deviceHash", o.optString("deviceHash", ""));
        } catch (JSONException e) {
            result.error("failed", "That check-in couldn't be made", null);
            return;
        }
        mesh.checkIn(code, message, (good, at, reason, text) -> ok(result, obj("ok", good, "at", at, "reason", reason, "message", text)));
    }

    // ---- the "Your event" home screen widget ----

    private void widget(JSONObject o, MethodChannel.Result result) {
        String code = o.optString("code", "");
        if (!EVENT_CODE.matcher(code).matches()) {
            result.error("failed", "Not an event this phone hosts", null);
            return;
        }
        if (o.optBoolean("clear")) {
            WidgetData.clear(this, code);
            ok(result, null);
            return;
        }
        String hostKey = o.optString("hostKey", "");
        if (!HOST_KEY.matcher(hostKey).matches()) {
            result.error("failed", "Not an event this phone hosts", null);
            return;
        }
        WidgetData.Event e = new WidgetData.Event();
        e.code = code;
        e.hostKey = hostKey;
        // The server's own limits (main-site/api/_lib/validate.js), so nothing longer is drawn.
        e.title = clip(o.optString("title", ""), 80);
        e.paused = o.optBoolean("paused");
        e.ended = o.optBoolean("ended");
        e.count = Math.max(0, o.optInt("count", 0));
        e.left = Math.max(0, o.optInt("left", 0));
        String latest = str(o, "latestName");
        e.latestName = latest == null || latest.isEmpty() ? null : clip(latest, 60);
        e.latestAt = WidgetData.parseTime(str(o, "latestAt"));
        WidgetData.fromPage(this, e);
        ok(result, null);
    }

    private static String clip(String text, int max) {
        if (text == null) return "";
        return text.codePointCount(0, text.length()) <= max ? text : text.substring(0, text.offsetByCodePoints(0, max));
    }
}
