/*
 * The app: the site at here.uwuapps.org in Capacitor's WebView (capacitor.config.json's
 * server.url), so the site's own updates reach it at once, with this app's plugin injected into
 * its pages for what a web page can't do (main-site/js/app-bridge.js):
 *
 *   HerePlugin         what the app can do: keeping the host's screen on, the QR code at full
 *                      brightness, saving the CSV, updating itself, and which notifications
 *                      you've turned on
 *   PushNotifications  Capacitor's, for Android's notification permission and the pushes
 *
 * Here: what the app was opened with (one of the site's own links, such as a scanned QR code, a
 * uwu://here/ link, or a tapped notification) opened in the page, the back button going back
 * through the page's history, and the notification channels.
 */
package org.uwuapps.here;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.WebView;

import androidx.activity.OnBackPressedCallback;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    static final String SITE = "https://here.uwuapps.org";
    static final String HOST = "here.uwuapps.org";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        registerPlugin(HerePlugin.class);
        Notifications.createChannels(this);
        super.onCreate(savedInstanceState);

        // Back goes back through the page's history, as in a browser. Off the first page, the
        // app goes to the background rather than closing, so a host's page keeps its place.
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                WebView web = bridge == null ? null : bridge.getWebView();
                if (web != null && web.canGoBack()) web.goBack();
                else moveTaskToBack(true);
            }
        });
    }

    // BridgeActivity calls this with the intent the app was opened with too, once the page has
    // started loading the site's home page.
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);

        // "Version 1.2.0 of uwuHere is out", tapped (main-site/api/push/release.js): straight to
        // the update window, which asks before downloading it. Taken off the intent so it isn't
        // asked again if Android recreates the activity with it.
        String type = intent.getStringExtra("type");
        if ("release".equals(type)) {
            UpdateActivity.start(this, true, intent.getStringExtra("version"));
            intent.removeExtra("type");
            return;
        }

        String url = pageFor(intent);
        if (url != null && bridge != null) bridge.getWebView().loadUrl(url);
    }

    // The site's page an intent asks for, or null for the home page as it is.
    static String pageFor(Intent intent) {
        if (intent == null) return null;

        // "Alex checked in", tapped (main-site/api/_lib/alerts.js): that event's host page.
        if ("checkin".equals(intent.getStringExtra("type"))) {
            String code = intent.getStringExtra("code");
            intent.removeExtra("type");
            if (code != null && code.matches("[A-Z0-9]{6}")) return SITE + "/host?id=" + code;
            return null;
        }

        Uri data = intent.getData();
        if (data == null) return null;
        // The site's own links, such as a host's QR code: https://here.uwuapps.org/join?id=CODE
        if ("https".equals(data.getScheme()) && HOST.equalsIgnoreCase(data.getHost())) {
            return data.toString();
        }
        // uwu://here/join?id=CODE to the same page on the site. uwu:// is shared by UwU Apps'
        // apps, each answering its own host.
        if ("uwu".equals(data.getScheme()) && "here".equalsIgnoreCase(data.getHost())) {
            String path = data.getEncodedPath();
            String query = data.getEncodedQuery();
            return SITE + (path == null || path.isEmpty() ? "/" : path) + (query == null ? "" : "?" + query);
        }
        return null;
    }
}
