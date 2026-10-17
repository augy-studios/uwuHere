/*
 * The home screen widget's event (EventWidget): the one this phone is hosting, kept in
 * SharedPreferences so the widget draws at once, even offline. Two ways in:
 *
 *   fromPage  the host page, each time it has the event from the server (HerePlugin.widget,
 *             main-site/js/app-widget.js)
 *   refresh   the widget asking /api/host itself, with the host key, as the host page does: its
 *             refresh button, and WidgetWorker every 15 minutes while the event is on
 *
 * One event at a time: the live one whose host page was opened last. Opening an ended event's
 * page doesn't push a live one out.
 */
package org.uwuapps.here;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;

import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class WidgetData {
    private static final String PREFS = "uwuhere";
    private static final String KEY = "widget.event";
    private static final String WORK = "event-widget";
    private static final Object LOCK = new Object();

    // The widget's network work, off the main thread (EventWidget's refresh button).
    static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    static final class Event {
        String code;
        String hostKey;
        String title = "";
        boolean paused;
        boolean ended;
        int count;
        int left;
        String latestName; // the last to check in, or null for nobody yet
        long latestAt;
        long fetchedAt; // when this copy came from the server, on this phone's clock
        boolean offline; // the last refresh couldn't reach the server

        JSONObject toJson() throws JSONException {
            JSONObject out = new JSONObject();
            out.put("code", code);
            out.put("hostKey", hostKey);
            out.put("title", title);
            out.put("paused", paused);
            out.put("ended", ended);
            out.put("count", count);
            out.put("left", left);
            out.put("latestName", latestName == null ? JSONObject.NULL : latestName);
            out.put("latestAt", latestAt);
            out.put("fetchedAt", fetchedAt);
            out.put("offline", offline);
            return out;
        }

        static Event fromJson(JSONObject in) {
            Event e = new Event();
            e.code = in.optString("code");
            e.hostKey = in.optString("hostKey");
            e.title = in.optString("title");
            e.paused = in.optBoolean("paused");
            e.ended = in.optBoolean("ended");
            e.count = in.optInt("count");
            e.left = in.optInt("left");
            e.latestName = in.isNull("latestName") ? null : in.optString("latestName");
            e.latestAt = in.optLong("latestAt");
            e.fetchedAt = in.optLong("fetchedAt");
            e.offline = in.optBoolean("offline");
            return e;
        }
    }

    // The server said this phone can't have the event any more: deleted, or a key that stopped
    // working.
    private static final class Gone extends Exception {}

    private WidgetData() {}

    static Event load(Context context) {
        String raw = prefs(context).getString(KEY, null);
        if (raw == null) return null;
        try {
            Event e = Event.fromJson(new JSONObject(raw));
            return HerePlugin.EVENT_CODE.matcher(e.code).matches() ? e : null;
        } catch (JSONException e) {
            return null;
        }
    }

    private static void save(Context context, Event e) {
        SharedPreferences.Editor edit = prefs(context).edit();
        try {
            if (e == null) edit.remove(KEY);
            else edit.putString(KEY, e.toJson().toString());
        } catch (JSONException ignored) {
            return; // Only strings, numbers and booleans: never happens.
        }
        edit.apply();
    }

    /** What the host page has just had from the server. */
    static void fromPage(Context context, Event e) {
        synchronized (LOCK) {
            Event current = load(context);
            boolean otherLive = current != null && !current.code.equals(e.code) && !current.ended;
            if (otherLive && e.ended) return;
            e.fetchedAt = System.currentTimeMillis();
            save(context, e);
        }
        EventWidget.drawAll(context, false);
        schedule(context);
    }

    /** The host page no longer has this event: forgotten, ended and deleted, or locked out. */
    static void clear(Context context, String code) {
        synchronized (LOCK) {
            Event current = load(context);
            if (current == null || !current.code.equals(code)) return;
            save(context, null);
        }
        EventWidget.drawAll(context, false);
        schedule(context);
    }

    /**
     * Asks the server for the event now, on the calling thread, which mustn't be the main one.
     * A copy the page sent while this was on its way is newer, and is kept.
     */
    static void refresh(Context context) {
        Event current = load(context);
        if (current == null) return;
        long started = System.currentTimeMillis();
        Event fresh = null;
        boolean gone = false;
        try {
            fresh = fetch(current);
        } catch (Gone g) {
            gone = true;
        } catch (IOException | JSONException e) {
            // Offline, or the server's having trouble: the copy stays, marked as old.
        }
        synchronized (LOCK) {
            Event now = load(context);
            if (now == null || !now.code.equals(current.code) || now.fetchedAt > started) return;
            if (gone) {
                save(context, null);
            } else if (fresh == null) {
                now.offline = true;
                save(context, now);
            } else {
                fresh.fetchedAt = System.currentTimeMillis();
                save(context, fresh);
            }
        }
    }

    // POST /api/host { code, hostKey, action: "get" }, as the host page asks
    // (main-site/api/host.js), made into the widget's few numbers.
    private static Event fetch(Event current) throws IOException, JSONException, Gone {
        JSONObject body = new JSONObject();
        body.put("code", current.code);
        body.put("hostKey", current.hostKey);
        body.put("action", "get");
        byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);

        HttpURLConnection conn = (HttpURLConnection) new URL(MainActivity.SITE + "/api/host").openConnection();
        conn.setConnectTimeout(10_000);
        conn.setReadTimeout(15_000);
        conn.setRequestMethod("POST");
        conn.setDoOutput(true);
        conn.setRequestProperty("Content-Type", "application/json");
        conn.setRequestProperty("User-Agent", "uwuHere for Android widget");
        try {
            try (OutputStream out = conn.getOutputStream()) {
                out.write(bytes);
            }
            int status = conn.getResponseCode();
            // 403 not-host, 404 not-found: this phone won't see the event again.
            if (status == 403 || status == 404) throw new Gone();
            if (status != 200) throw new IOException("The server answered " + status);
            JSONObject data;
            try (InputStream in = conn.getInputStream()) {
                data = new JSONObject(read(in)).getJSONObject("data");
            }
            return summarise(current, data.getJSONObject("event"), data.getJSONArray("attendees"));
        } finally {
            conn.disconnect();
        }
    }

    // The same numbers main-site/js/app-widget.js works out from the same answer.
    private static Event summarise(Event current, JSONObject event, JSONArray attendees) throws JSONException {
        Event e = new Event();
        e.code = current.code;
        e.hostKey = current.hostKey;
        e.title = event.isNull("title") ? "" : event.optString("title");
        e.paused = event.optBoolean("paused");
        e.ended = event.optBoolean("ended");
        e.count = attendees.length();
        for (int i = 0; i < attendees.length(); i++) {
            JSONObject a = attendees.getJSONObject(i);
            if (!a.isNull("leftEarlyAt")) e.left++;
            long at = parseTime(a.isNull("checkedInAt") ? null : a.optString("checkedInAt"));
            if (e.latestName == null || at > e.latestAt) {
                e.latestName = a.optString("name");
                e.latestAt = at;
            }
        }
        return e;
    }

    private static final Pattern ISO = Pattern.compile(
            "(\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d)(?:\\.(\\d{1,9}))?(Z|[+-]\\d\\d:\\d\\d)");

    /**
     * An ISO time from the server, such as 2026-10-18T02:42:00.123456+00:00, in milliseconds, or 0.
     * By hand, as java.time is Android 8 and later, and SimpleDateFormat can't read microseconds.
     */
    static long parseTime(String iso) {
        if (iso == null) return 0;
        Matcher m = ISO.matcher(iso);
        if (!m.matches()) return 0;
        try {
            SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US);
            Date date = format.parse(m.group(1) + m.group(3));
            if (date == null) return 0;
            String fraction = m.group(2) == null ? "" : m.group(2);
            int millis = fraction.isEmpty() ? 0 : Integer.parseInt((fraction + "00").substring(0, 3));
            return date.getTime() + millis;
        } catch (ParseException | NumberFormatException e) {
            return 0;
        }
    }

    private static String read(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        for (int n; (n = in.read(buffer)) != -1; ) out.write(buffer, 0, n);
        return out.toString("UTF-8");
    }

    /* ---- the 15-minute refresh ---- */

    // Only while there's a widget to draw and an event still taking check-ins.
    static boolean needed(Context context) {
        int[] ids = AppWidgetManager.getInstance(context).getAppWidgetIds(new ComponentName(context, EventWidget.class));
        Event e = load(context);
        return ids != null && ids.length > 0 && e != null && !e.ended;
    }

    /** Starts the refresh if it's needed and stops it if not. Safe to call any number of times. */
    static void schedule(Context context) {
        WorkManager work = WorkManager.getInstance(context);
        if (!needed(context)) {
            work.cancelUniqueWork(WORK);
            return;
        }
        // 15 minutes is the least Android allows. Only with a connection, as there's nothing to
        // learn without one.
        PeriodicWorkRequest request = new PeriodicWorkRequest.Builder(WidgetWorker.class, 15, TimeUnit.MINUTES)
                .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build();
        work.enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP, request);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
