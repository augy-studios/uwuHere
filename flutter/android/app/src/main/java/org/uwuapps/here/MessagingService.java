package org.uwuapps.here;

import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.util.Map;

/**
 * The site's pushes (main-site/api/_lib/fcm.js), on the topics the bell's switches join:
 * "Alex checked in" (an event's own topic, api/_lib/alerts.js), "Version x.y.z of uwuHere is out"
 * (uwuhere-releases, api/push/release.js) and news (uwuhere-news, from the Firebase console).
 * While the app's in the background Android shows them itself, from the message's notification
 * part, on the channel it names; this shows them while the app's in front, where Android
 * wouldn't. Either way, tapping one opens the app on what it's about (MainActivity.linkOf): the
 * event's host page, or the Updates page.
 */
public class MessagingService extends FirebaseMessagingService {
    @Override
    public void onMessageReceived(@NonNull RemoteMessage message) {
        RemoteMessage.Notification shown = message.getNotification();
        Map<String, String> data = message.getData();
        String title = shown != null ? shown.getTitle() : data.get("title");
        String body = shown != null ? shown.getBody() : data.get("body");
        if (title == null && body == null) return;
        Notifications.createChannels(this);
        String type = data.get("type");
        String channel = shown != null && shown.getChannelId() != null ? shown.getChannelId()
                : ("checkin".equals(type) ? Notifications.CHECKINS : "release".equals(type) ? Notifications.RELEASES : Notifications.NEWS);
        Intent open = new Intent(this, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        for (Map.Entry<String, String> e : data.entrySet()) open.putExtra(e.getKey(), e.getValue());
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        String tag = shown != null && shown.getTag() != null ? shown.getTag() : (type == null ? "news" : type);
        PendingIntent tap = PendingIntent.getActivity(this, tag.hashCode(), open, flags);
        NotificationCompat.Builder n = new NotificationCompat.Builder(this, channel)
                .setSmallIcon(R.drawable.ic_notification_icon)
                .setColor(getColor(R.color.notification_colour))
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(tap);
        NotificationManager nm = getSystemService(NotificationManager.class);
        // One per tag, as the site sends them: a busy event updates one notification.
        if (nm != null) nm.notify(tag, 1, n.build());
    }

    @Override
    public void onNewToken(@NonNull String token) {
        // Topics need no token kept on the server.
    }
}
