/*
 * Checking in by Bluetooth, app to app: the host's phone and an attendee's phone, both running
 * this app, talk directly over Google's Nearby Connections (Bluetooth, and wifi between the two
 * phones once they've met), with no internet needed on either. Only attendees who have the app
 * can do this; everyone else checks in the other ways the event allows.
 *
 * Host: while the host page has Bluetooth on (HerePlugin.bluetooth), this phone advertises as
 * "uwuhere:CODE". Each check-in that arrives is handed to the page ("meshCheckin"), which records
 * it the same way as a same-wifi one, straight to the server or into its outbox
 * (main-site/js/host.js), and its answer goes back to the attendee (answer()).
 *
 * Attendee: pressing the button on the join page in the app (main-site/js/join.js) looks for that
 * name, connects, sends { v, type: "checkin", code, name, note, deviceHash }, and waits for
 * { type: "checked-in", at } or { type: "refused", message }. Then it hangs up.
 *
 * Needs Google Play services on both phones, which nearly every Android phone sold with Google's
 * apps has.
 */
package org.uwuapps.here;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.GoogleApiAvailability;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.nearby.Nearby;
import com.google.android.gms.nearby.connection.AdvertisingOptions;
import com.google.android.gms.nearby.connection.ConnectionInfo;
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback;
import com.google.android.gms.nearby.connection.ConnectionResolution;
import com.google.android.gms.nearby.connection.ConnectionsClient;
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes;
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo;
import com.google.android.gms.nearby.connection.DiscoveryOptions;
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback;
import com.google.android.gms.nearby.connection.Payload;
import com.google.android.gms.nearby.connection.PayloadCallback;
import com.google.android.gms.nearby.connection.PayloadTransferUpdate;
import com.google.android.gms.nearby.connection.Strategy;

import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

final class Mesh {
    /** The host page, told about each check-in; false if no page is listening. */
    interface Host {
        boolean checkIn(String id, String name, String note, String deviceHash);
    }

    interface Started {
        void started();

        void failed(String message);
    }

    /** The attendee's outcome, once, on the main thread. `reason` is null when ok. */
    interface Outcome {
        void done(boolean ok, String at, String reason, String message);
    }

    private static final String SERVICE_ID = "org.uwuapps.here.checkin";
    private static final String NAME_PREFIX = "uwuhere:";
    private static final int PROTOCOL = 1;
    private static final Strategy STRATEGY = Strategy.P2P_STAR;

    private static final long FIND_MS = 12_000; // looking for the host's phone
    private static final long ANSWER_MS = 25_000; // connecting, and the host page's answer
    private static final long HOST_ANSWER_MS = 18_000; // the host page, before the host gives up
    private static final long HANG_UP_MS = 3_000; // after answering, so the answer gets there

    private final ConnectionsClient client;
    private final Handler main = new Handler(Looper.getMainLooper());

    // Host
    private String advertising;
    private Host host;
    private final Map<String, String> waiting = new ConcurrentHashMap<>(); // check-in id -> endpoint

    // Attendee
    private boolean checking;

    Mesh(Context context) {
        client = Nearby.getConnectionsClient(context.getApplicationContext());
    }

    static boolean available(Context context) {
        return GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS;
    }

    /* ---- host ---- */

    void advertise(String code, Host page, Started result) {
        host = page;
        if (code.equals(advertising)) {
            result.started();
            return;
        }
        stopAdvertising();
        AdvertisingOptions options = new AdvertisingOptions.Builder().setStrategy(STRATEGY).build();
        client.startAdvertising(NAME_PREFIX + code, SERVICE_ID, hostConnections, options)
                .addOnSuccessListener(v -> {
                    advertising = code;
                    result.started();
                })
                .addOnFailureListener(e -> {
                    if (status(e) == ConnectionsStatusCodes.STATUS_ALREADY_ADVERTISING) {
                        advertising = code;
                        result.started();
                    } else {
                        result.failed(failure(e));
                    }
                });
    }

    void stopAdvertising() {
        if (advertising == null) return;
        advertising = null;
        client.stopAdvertising();
        for (Map.Entry<String, String> w : waiting.entrySet()) {
            send(w.getValue(), refused("The host stopped Bluetooth check-in."));
        }
        waiting.clear();
    }

    boolean advertising() {
        return advertising != null;
    }

    /** The host page's answer to check-in `id`. */
    void answer(String id, boolean ok, String at, String message) {
        String endpoint = waiting.remove(id);
        if (endpoint == null) return;
        JSONObject out = new JSONObject();
        try {
            if (ok) {
                out.put("type", "checked-in");
                out.put("at", at == null ? JSONObject.NULL : at);
            } else {
                out = refused(message == null || message.isEmpty() ? "The host couldn't check you in." : message);
            }
        } catch (JSONException ignored) {
            // Plain values: can't happen.
        }
        send(endpoint, out);
    }

    private final ConnectionLifecycleCallback hostConnections = new ConnectionLifecycleCallback() {
        @Override
        public void onConnectionInitiated(String endpoint, ConnectionInfo info) {
            // Anyone may knock: what they send is checked, as with same wifi.
            client.acceptConnection(endpoint, hostPayloads);
        }

        @Override
        public void onConnectionResult(String endpoint, ConnectionResolution result) {
        }

        @Override
        public void onDisconnected(String endpoint) {
            waiting.values().remove(endpoint);
        }
    };

    private final PayloadCallback hostPayloads = new PayloadCallback() {
        @Override
        public void onPayloadReceived(String endpoint, Payload payload) {
            JSONObject in = read(payload);
            String code = advertising;
            if (in == null || !"checkin".equals(in.optString("type"))) {
                send(endpoint, refused("That check-in couldn't be read. Try again."));
                return;
            }
            if (in.optInt("v") != PROTOCOL) {
                send(endpoint, refused("One of the two phones needs the newest uwuHere app."));
                return;
            }
            if (code == null || !code.equals(in.optString("code"))) {
                send(endpoint, refused("That's a different event's host."));
                return;
            }
            String id = UUID.randomUUID().toString();
            waiting.put(id, endpoint);
            Host page = host;
            String note = in.isNull("note") ? "" : in.optString("note", "");
            if (page == null || !page.checkIn(id, in.optString("name", ""), note, in.optString("deviceHash", ""))) {
                waiting.remove(id);
                send(endpoint, refused("The host's event page isn't open. Ask the host to open it, then try again."));
                return;
            }
            main.postDelayed(() -> {
                String late = waiting.remove(id);
                if (late != null) send(late, refused("The host's phone didn't answer. Try again."));
            }, HOST_ANSWER_MS);
        }

        @Override
        public void onPayloadTransferUpdate(String endpoint, PayloadTransferUpdate update) {
        }
    };

    private void send(String endpoint, JSONObject out) {
        client.sendPayload(endpoint, Payload.fromBytes(out.toString().getBytes(StandardCharsets.UTF_8)));
        main.postDelayed(() -> client.disconnectFromEndpoint(endpoint), HANG_UP_MS);
    }

    /* ---- attendee ---- */

    void checkIn(String code, JSONObject message, Outcome outcome) {
        if (checking) {
            outcome.done(false, null, "busy", "Already checking in. Wait a moment.");
            return;
        }
        checking = true;
        String wanted = NAME_PREFIX + code;
        String[] endpoint = {null};
        boolean[] finished = {false};
        Runnable[] timeout = {null};

        // Ends it, once: stops looking, hangs up, and answers.
        Outcome finish = (ok, at, reason, text) -> {
            if (finished[0]) return;
            finished[0] = true;
            checking = false;
            if (timeout[0] != null) main.removeCallbacks(timeout[0]);
            client.stopDiscovery();
            if (endpoint[0] != null) client.disconnectFromEndpoint(endpoint[0]);
            outcome.done(ok, at, reason, text);
        };

        PayloadCallback answers = new PayloadCallback() {
            @Override
            public void onPayloadReceived(String from, Payload payload) {
                JSONObject in = read(payload);
                if (in != null && "checked-in".equals(in.optString("type"))) {
                    finish.done(true, in.isNull("at") ? null : in.optString("at", null), null, null);
                } else {
                    String text = in == null ? "" : in.optString("message", "");
                    finish.done(false, null, "refused", text.isEmpty() ? "The host couldn't check you in." : text);
                }
            }

            @Override
            public void onPayloadTransferUpdate(String from, PayloadTransferUpdate update) {
            }
        };

        ConnectionLifecycleCallback connection = new ConnectionLifecycleCallback() {
            @Override
            public void onConnectionInitiated(String to, ConnectionInfo info) {
                client.acceptConnection(to, answers);
            }

            @Override
            public void onConnectionResult(String to, ConnectionResolution result) {
                if (result.getStatus().isSuccess()) {
                    client.sendPayload(to, Payload.fromBytes(message.toString().getBytes(StandardCharsets.UTF_8)));
                } else {
                    finish.done(false, null, "failed", "The host's phone didn't take the connection. Try again.");
                }
            }

            @Override
            public void onDisconnected(String to) {
                finish.done(false, null, "dropped", "The connection to the host's phone dropped. Try again.");
            }
        };

        EndpointDiscoveryCallback discovery = new EndpointDiscoveryCallback() {
            @Override
            public void onEndpointFound(String found, DiscoveredEndpointInfo info) {
                if (endpoint[0] != null || finished[0] || !wanted.equals(info.getEndpointName())) return;
                endpoint[0] = found;
                client.stopDiscovery();
                main.removeCallbacks(timeout[0]);
                timeout[0] = () -> finish.done(false, null, "timeout", "The host's phone didn't answer. Try again.");
                main.postDelayed(timeout[0], ANSWER_MS);
                client.requestConnection("uwuhere-attendee", found, connection)
                        .addOnFailureListener(e -> finish.done(false, null, "failed", "Couldn't connect to the host's phone. " + failure(e)));
            }

            @Override
            public void onEndpointLost(String lost) {
            }
        };

        timeout[0] = () -> finish.done(false, null, "not-found",
                "Couldn't find the host's phone by Bluetooth. Check the host has Bluetooth check-in on, and that you're near them.");
        main.postDelayed(timeout[0], FIND_MS);

        client.stopDiscovery();
        DiscoveryOptions options = new DiscoveryOptions.Builder().setStrategy(STRATEGY).build();
        client.startDiscovery(SERVICE_ID, discovery, options)
                .addOnFailureListener(e -> finish.done(false, null, "failed", failure(e)));
    }

    /* ---- shared ---- */

    private static JSONObject read(Payload payload) {
        if (payload.getType() != Payload.Type.BYTES || payload.asBytes() == null) return null;
        try {
            return new JSONObject(new String(payload.asBytes(), StandardCharsets.UTF_8));
        } catch (JSONException e) {
            return null;
        }
    }

    private static JSONObject refused(String message) {
        JSONObject out = new JSONObject();
        try {
            out.put("type", "refused");
            out.put("message", message);
        } catch (JSONException ignored) {
            // Plain values: can't happen.
        }
        return out;
    }

    private static int status(Exception e) {
        return e instanceof ApiException ? ((ApiException) e).getStatusCode() : -1;
    }

    private static String failure(Exception e) {
        int code = status(e);
        if (code == ConnectionsStatusCodes.STATUS_BLUETOOTH_ERROR) return "Turn Bluetooth off and on again, then try again.";
        if (code == ConnectionsStatusCodes.STATUS_RADIO_ERROR) return "Turn Bluetooth on, then try again.";
        return "Bluetooth check-in didn't start. Try again.";
    }
}
