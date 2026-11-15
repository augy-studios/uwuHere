/*
 * The "Your event" home screen widget: the event this phone is hosting (WidgetData), with how
 * many are here, how many left early, who checked in last, and its code. Tapping it opens the
 * event's host page; with no event yet, the home page's "Host an event" form.
 *
 * Drawn from the stored copy, so it shows at once and offline. The copy is new each time the
 * host page has the event from the server, and the widget refreshes it itself from its refresh
 * button and every 15 minutes while the event is on (WidgetWorker).
 *
 * Follows the phone's light or dark mode (values-night/widget.xml), not the site's. Rows go as
 * the widget gets shorter: the detail line, then the code.
 */
package org.uwuapps.here;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.text.TextUtils;
import android.text.format.DateUtils;
import android.view.View;
import android.widget.RemoteViews;

import java.util.ArrayList;
import java.util.List;

public class EventWidget extends AppWidgetProvider {
    private static final String REFRESH = "org.uwuapps.here.widget.REFRESH";
    // A copy older than this is refreshed as the widget is added.
    private static final long STALE_MS = 5 * 60_000;

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        drawAll(context, false);
        WidgetData.schedule(context);
        WidgetData.Event e = WidgetData.load(context);
        if (e != null && !e.ended && System.currentTimeMillis() - e.fetchedAt > STALE_MS) refresh(context);
    }

    @Override
    public void onAppWidgetOptionsChanged(Context context, AppWidgetManager manager, int id, Bundle options) {
        manager.updateAppWidget(id, views(context, manager, id, WidgetData.load(context), false));
    }

    @Override
    public void onDeleted(Context context, int[] ids) {
        WidgetData.schedule(context);
    }

    @Override
    public void onDisabled(Context context) {
        WidgetData.schedule(context);
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (REFRESH.equals(intent.getAction())) refresh(context);
    }

    // "Refreshing…" at once, then the server's answer, kept alive with goAsync while it comes.
    private void refresh(Context context) {
        PendingResult pending = goAsync();
        drawAll(context, true);
        WidgetData.EXECUTOR.execute(() -> {
            try {
                WidgetData.refresh(context);
                drawAll(context, false);
                WidgetData.schedule(context);
            } finally {
                pending.finish();
            }
        });
    }

    static void drawAll(Context context, boolean refreshing) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, EventWidget.class));
        if (ids == null || ids.length == 0) return;
        WidgetData.Event e = WidgetData.load(context);
        for (int id : ids) manager.updateAppWidget(id, views(context, manager, id, e, refreshing));
    }

    private static RemoteViews views(Context context, AppWidgetManager manager, int id, WidgetData.Event e, boolean refreshing) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_event);
        Bundle options = manager.getAppWidgetOptions(id);
        int height = options == null ? 0 : options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0);
        // 0 is a launcher that doesn't say: everything.
        boolean roomForDetail = height == 0 || height >= 105;
        boolean roomForFooter = height == 0 || height >= 90;

        if (e == null) {
            views.setTextViewText(R.id.widget_title, "uwuHere");
            views.setViewVisibility(R.id.widget_refresh, View.GONE);
            views.setTextViewText(R.id.widget_count, "No event yet");
            views.setTextViewText(R.id.widget_detail, "Tap to host one. Your event shows here.");
            views.setViewVisibility(R.id.widget_detail, roomForDetail ? View.VISIBLE : View.GONE);
            views.setViewVisibility(R.id.widget_footer, View.GONE);
            views.setOnClickPendingIntent(android.R.id.background, open(context, "/#host", 3));
            return views;
        }

        views.setTextViewText(R.id.widget_title, e.title.isEmpty() ? "Untitled event" : e.title);
        views.setViewVisibility(R.id.widget_refresh, View.VISIBLE);
        views.setTextViewText(R.id.widget_count, e.count == 0 ? "Nobody yet" : e.count + " here");

        List<String> detail = new ArrayList<>();
        if (e.ended) detail.add("Ended");
        else if (e.paused) detail.add("Paused");
        if (e.left > 0) detail.add(e.left + " left early");
        if (e.latestName != null) detail.add("Latest: " + e.latestName + ", " + when(context, e.latestAt));
        views.setTextViewText(R.id.widget_detail, TextUtils.join(" · ", detail));
        views.setViewVisibility(R.id.widget_detail, roomForDetail && !detail.isEmpty() ? View.VISIBLE : View.GONE);

        String status = refreshing ? "Refreshing…"
                : e.offline ? "Offline, as of " + when(context, e.fetchedAt)
                : "Updated " + when(context, e.fetchedAt);
        views.setTextViewText(R.id.widget_footer, e.code + " · " + status);
        views.setViewVisibility(R.id.widget_footer, roomForFooter ? View.VISIBLE : View.GONE);

        views.setOnClickPendingIntent(android.R.id.background, open(context, "/host?id=" + e.code, 1));
        Intent refresh = new Intent(context, EventWidget.class).setAction(REFRESH);
        views.setOnClickPendingIntent(R.id.widget_refresh, PendingIntent.getBroadcast(context, 2, refresh,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT));
        return views;
    }

    // The time today, or the date on another day, as this phone writes them (12 or 24 hours).
    private static String when(Context context, long millis) {
        if (millis <= 0) return "a while ago";
        int flags = DateUtils.isToday(millis) ? DateUtils.FORMAT_SHOW_TIME
                : DateUtils.FORMAT_SHOW_DATE | DateUtils.FORMAT_ABBREV_MONTH | DateUtils.FORMAT_NO_YEAR;
        return DateUtils.formatDateTime(context, millis, flags);
    }

    /** A page of the site, opened in the app (MainActivity.pageFor takes the site's own links). */
    static PendingIntent open(Context context, String path, int requestCode) {
        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(MainActivity.SITE + path), context, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return PendingIntent.getActivity(context, requestCode, intent,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }
}
