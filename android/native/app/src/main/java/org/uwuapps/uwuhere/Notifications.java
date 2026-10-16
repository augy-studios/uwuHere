/*
 * The app's notification channels, each its own switch in Android's settings for the app:
 *
 *   checkins  somebody checked in by location, or left early, at an event you host
 *             (main-site/api/_lib/alerts.js)
 *   releases  a new version of the app is out (main-site/api/push/release.js)
 *   news      news from uwuHere, sent from the Firebase console (android/FIREBASE-SETUP.md)
 *
 * All three come from FCM topics you join with the bell in the Edge Tray (HerePlugin.setTopic),
 * and the pushes name these channels (main-site/api/_lib/fcm.js). Android only takes a channel's
 * sound and importance from when it's made, so changing one means a new id.
 */
package org.uwuapps.uwuhere;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.os.Build;

final class Notifications {
    static final String CHECKINS = "checkins";
    static final String RELEASES = "releases";
    static final String NEWS = "news";

    private Notifications() {}

    static void createChannels(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager = context.getSystemService(NotificationManager.class);

        // Quiet: a busy event is one check-in after another, each replacing the one before
        // (the push's tag), and a sound for every one would be too much.
        NotificationChannel checkins = new NotificationChannel(CHECKINS, "Check-ins",
                NotificationManager.IMPORTANCE_LOW);
        checkins.setDescription("Who checked in by location or left early, at events you host");

        NotificationChannel releases = new NotificationChannel(RELEASES, "New versions",
                NotificationManager.IMPORTANCE_DEFAULT);
        releases.setDescription("When a new version of the app is out");

        NotificationChannel news = new NotificationChannel(NEWS, "News from uwuHere",
                NotificationManager.IMPORTANCE_DEFAULT);
        news.setDescription("Now and then: new features, and other news");

        manager.createNotificationChannel(checkins);
        manager.createNotificationChannel(releases);
        manager.createNotificationChannel(news);
    }
}
