/*
 * Checking in with no internet at all: this phone becomes a wifi hotspot of its own (Android's
 * local-only hotspot, which shares no internet) and serves a check-in page on it (LocalServer,
 * res/raw/hotspot_page.html). Attendees join the hotspot from one QR code on the host page and
 * open the page from a second, with no app, iPhones included. Being on the hotspot is the proof
 * they're here: it only reaches across a room or so.
 *
 * Each check-in is handed to the host page ("hotspotCheckin"), which records it the same way as
 * a same-wifi one: straight to the server, or into its outbox to send once it's back online
 * (main-site/js/host.js). The attendee's request waits for the page's answer (answer()), so they
 * see whether it worked. With the host page closed, there's nobody to answer, and they're told so.
 *
 * Android names the hotspot and its password itself, fresh each time, and turns the phone's own
 * wifi off while it's on if the phone can't do both. It stops when the host page stops it, when
 * the app closes, or when Android needs the wifi for something else ("hotspotStopped").
 */
package org.uwuapps.here;

import android.content.Context;
import android.net.wifi.SoftApConfiguration;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.RequiresApi;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

final class Hotspot {
    /** What the plugin hears from the hotspot. */
    interface Listener {
        /** Tells the host page; false if no page is listening. */
        boolean checkIn(String id, String name, String note, String deviceHash);

        void stopped();
    }

    /** How starting went: started(...) or failed(state, message), once, on the main thread. */
    interface Started {
        void started(String ssid, String password, String security, String url);

        void failed(String state, String message);
    }

    private static final Pattern DEVICE = Pattern.compile("[A-Za-z0-9-]{16,64}");
    // As long as the attendee waits for the host page. Its server request takes most of it.
    private static final long ANSWER_WAIT_S = 15;

    private final Context context;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Map<String, Waiting> waiting = new ConcurrentHashMap<>();

    private WifiManager.LocalOnlyHotspotReservation reservation;
    private LocalServer server;
    private String ssid, password, security, url;
    private boolean starting;

    Hotspot(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    static boolean supported() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O;
    }

    boolean on() {
        return server != null;
    }

    /** Starts, or answers with the hotspot already running. `event` is what the page shows. */
    @RequiresApi(api = Build.VERSION_CODES.O)
    void start(JSONObject event, Started result) {
        if (server != null) {
            result.started(ssid, password, security, url);
            return;
        }
        if (starting) {
            result.failed("failed", "The hotspot is already starting. Try again in a moment.");
            return;
        }
        WifiManager wifi = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
        if (wifi == null) {
            result.failed("unsupported", "This phone can't make a hotspot.");
            return;
        }

        String page;
        try {
            page = page(event);
        } catch (IOException e) {
            result.failed("failed", "The check-in page couldn't be made.");
            return;
        }

        Set<InetAddress> before = addresses();
        starting = true;
        try {
            wifi.startLocalOnlyHotspot(new WifiManager.LocalOnlyHotspotCallback() {
                @Override
                public void onStarted(WifiManager.LocalOnlyHotspotReservation started) {
                    reservation = started;
                    readConfig(started);
                    // The hotspot's address can take a moment to appear: found off the main thread.
                    new Thread(() -> serve(before, page, result), "uwuhere-hotspot-start").start();
                }

                @Override
                public void onStopped() {
                    main.post(() -> {
                        boolean was = server != null;
                        shutDown();
                        if (was) listener.stopped();
                    });
                }

                @Override
                public void onFailed(int reason) {
                    starting = false;
                    if (reason == ERROR_TETHERING_DISALLOWED) {
                        result.failed("busy", "This phone doesn't allow a hotspot right now.");
                    } else if (reason == ERROR_INCOMPATIBLE_MODE) {
                        result.failed("busy", "Turn off this phone's own hotspot first, then try again.");
                    } else if (reason == ERROR_NO_CHANNEL) {
                        result.failed("failed", "No free wifi channel for a hotspot here. Try again in a moment.");
                    } else {
                        result.failed("failed", "The hotspot didn't start. Try again.");
                    }
                }
            }, main);
        } catch (SecurityException e) {
            starting = false;
            result.failed("denied", "uwuHere isn't allowed to make a hotspot. Allow it in the app's settings.");
        } catch (IllegalStateException e) {
            starting = false;
            result.failed("busy", "Another app's hotspot is on. Turn it off, then try again.");
        }
    }

    private void serve(Set<InetAddress> before, String page, Started result) {
        InetAddress address = null;
        for (int i = 0; i < 25 && address == null; i++) {
            address = hotspotAddress(before);
            if (address == null) sleep(200);
        }
        if (address == null) {
            main.post(() -> {
                stop();
                result.failed("failed", "The hotspot started but has no address. Try again.");
            });
            return;
        }
        try {
            LocalServer started = new LocalServer(address, page, this::onRequest);
            String link = "http://" + address.getHostAddress() + ":" + started.port() + "/";
            main.post(() -> {
                starting = false;
                if (reservation == null) {
                    // Stopped while this was starting.
                    started.close();
                    result.failed("failed", "The hotspot stopped as it started. Try again.");
                    return;
                }
                server = started;
                url = link;
                result.started(ssid, password, security, url);
            });
        } catch (IOException e) {
            main.post(() -> {
                stop();
                result.failed("failed", "The check-in page couldn't start. Try again.");
            });
        }
    }

    void stop() {
        shutDown();
    }

    private void shutDown() {
        starting = false;
        if (server != null) server.close();
        server = null;
        if (reservation != null) reservation.close();
        reservation = null;
        ssid = password = security = url = null;
        for (Waiting w : waiting.values()) w.give(503, "The host stopped the hotspot.", null);
        waiting.clear();
    }

    /** The host page's answer to check-in `id`. */
    void answer(String id, boolean ok, String at, String message) {
        Waiting w = waiting.remove(id);
        if (w == null) return;
        if (ok) w.give(200, null, at);
        else w.give(409, message == null || message.isEmpty() ? "The host couldn't check you in." : message, null);
    }

    // On one of LocalServer's worker threads.
    private LocalServer.Answer onRequest(String body) {
        String name, note, device;
        try {
            JSONObject in = new JSONObject(body);
            name = in.optString("name", "").trim();
            note = in.isNull("note") ? "" : in.optString("note", "").trim();
            device = in.optString("device", "");
        } catch (JSONException e) {
            return error(400, "That check-in couldn't be read. Try again.");
        }
        if (name.isEmpty() || name.length() > 200 || note.length() > 400) return error(422, "Type your name, then try again.");
        if (!DEVICE.matcher(device).matches()) return error(400, "This browser's check-in id is missing. Reload and try again.");

        String id = UUID.randomUUID().toString();
        Waiting w = new Waiting();
        waiting.put(id, w);
        if (!listener.checkIn(id, name, note, sha256(device))) {
            waiting.remove(id);
            return error(503, "The host's event page isn't open. Ask the host to open it, then try again.");
        }
        try {
            if (!w.done.await(ANSWER_WAIT_S, TimeUnit.SECONDS)) {
                waiting.remove(id);
                return error(504, "The host's phone didn't answer. Try again.");
            }
        } catch (InterruptedException e) {
            waiting.remove(id);
            Thread.currentThread().interrupt();
            return error(503, "The host stopped the hotspot.");
        }
        return w.answer;
    }

    private static final class Waiting {
        final CountDownLatch done = new CountDownLatch(1);
        volatile LocalServer.Answer answer;

        void give(int status, String error, String at) {
            JSONObject out = new JSONObject();
            try {
                out.put("ok", error == null);
                if (error != null) out.put("error", error);
                if (at != null) out.put("at", at);
            } catch (JSONException ignored) {
                // Plain values: can't happen.
            }
            answer = new LocalServer.Answer(status, out.toString());
            done.countDown();
        }
    }

    private static LocalServer.Answer error(int status, String message) {
        Waiting w = new Waiting();
        w.give(status, message, null);
        return w.answer;
    }

    // The page with the event's details in it. "<" is escaped so nothing in a title can end the
    // script it sits in.
    private String page(JSONObject event) throws IOException {
        try (InputStream in = context.getResources().openRawResource(R.raw.hotspot_page)) {
            ByteArrayOutputStream all = new ByteArrayOutputStream();
            byte[] chunk = new byte[4096];
            for (int n; (n = in.read(chunk)) > 0; ) all.write(chunk, 0, n);
            String json = event.toString().replace("<", "\\u003c");
            return new String(all.toByteArray(), StandardCharsets.UTF_8).replace("__EVENT__", json);
        }
    }

    @SuppressWarnings("deprecation")
    private void readConfig(WifiManager.LocalOnlyHotspotReservation r) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            SoftApConfiguration c = r.getSoftApConfiguration();
            ssid = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && c.getWifiSsid() != null
                    ? c.getWifiSsid().toString()
                    : c.getSsid();
            password = c.getPassphrase();
            int type = c.getSecurityType();
            security = type == SoftApConfiguration.SECURITY_TYPE_OPEN ? "nopass"
                    : type == SoftApConfiguration.SECURITY_TYPE_WPA3_SAE ? "SAE" : "WPA";
        } else {
            WifiConfiguration c = r.getWifiConfiguration();
            ssid = c == null ? null : c.SSID;
            password = c == null ? null : c.preSharedKey;
            security = password == null ? "nopass" : "WPA";
        }
        ssid = unquote(ssid);
        password = unquote(password);
    }

    private static String unquote(String s) {
        if (s != null && s.length() >= 2 && s.startsWith("\"") && s.endsWith("\"")) return s.substring(1, s.length() - 1);
        return s;
    }

    // Every IPv4 address this phone has, on any interface that's up.
    private static Set<InetAddress> addresses() {
        Set<InetAddress> out = new HashSet<>();
        for (Object[] pair : interfaceAddresses()) out.add((InetAddress) pair[1]);
        return out;
    }

    private static boolean hotspotName(String name) {
        return name.startsWith("ap") || name.startsWith("swlan") || name.startsWith("softap");
    }

    // The hotspot's: a private address that wasn't there before it started, on a wifi interface
    // first (mobile data can get a new one meanwhile), then on any; failing those, one on an
    // interface Android names only for hotspots.
    private static InetAddress hotspotAddress(Set<InetAddress> before) {
        List<Object[]> now = interfaceAddresses();
        for (Object[] pair : now) {
            String name = (String) pair[0];
            InetAddress a = (InetAddress) pair[1];
            if ((name.startsWith("wlan") || hotspotName(name)) && !before.contains(a) && a.isSiteLocalAddress()) return a;
        }
        for (Object[] pair : now) {
            InetAddress a = (InetAddress) pair[1];
            if (!before.contains(a) && a.isSiteLocalAddress()) return a;
        }
        for (Object[] pair : now) {
            InetAddress a = (InetAddress) pair[1];
            if (hotspotName((String) pair[0]) && a.isSiteLocalAddress()) return a;
        }
        return null;
    }

    // { interface name, IPv4 address } for each interface that's up.
    private static List<Object[]> interfaceAddresses() {
        List<Object[]> out = new ArrayList<>();
        try {
            for (NetworkInterface nif : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!nif.isUp() || nif.isLoopback()) continue;
                for (InetAddress a : Collections.list(nif.getInetAddresses())) {
                    if (a instanceof Inet4Address) out.add(new Object[] {nif.getName(), a});
                }
            }
        } catch (Exception e) {
            // No list of interfaces: nothing found.
        }
        return out;
    }

    private static String sha256(String text) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte b : hash) hex.append(String.format("%02x", b));
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
