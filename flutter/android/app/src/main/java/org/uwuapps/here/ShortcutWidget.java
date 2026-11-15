/*
 * The "Check in" home screen widget: two buttons, straight to the home page's code box
 * (Check in, /#join) or its "Host an event" form (Host, /#host), which main-site/js/home.js
 * scrolls to. Nothing to fetch or keep. Narrower than about two cells it's Check in alone, and
 * narrower still the icon alone.
 */
package org.uwuapps.here;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.os.Bundle;
import android.view.View;
import android.widget.RemoteViews;

public class ShortcutWidget extends AppWidgetProvider {
    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) manager.updateAppWidget(id, views(context, manager, id));
    }

    @Override
    public void onAppWidgetOptionsChanged(Context context, AppWidgetManager manager, int id, Bundle options) {
        manager.updateAppWidget(id, views(context, manager, id));
    }

    private static RemoteViews views(Context context, AppWidgetManager manager, int id) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_shortcut);
        Bundle options = manager.getAppWidgetOptions(id);
        int width = options == null ? 0 : options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0);
        // 0 is a launcher that doesn't say: both buttons, with words.
        boolean both = width == 0 || width >= 150;
        boolean words = width == 0 || width >= 90;

        views.setViewVisibility(R.id.widget_host, both ? View.VISIBLE : View.GONE);
        views.setViewVisibility(R.id.widget_join_label, words ? View.VISIBLE : View.GONE);
        views.setOnClickPendingIntent(R.id.widget_join, EventWidget.open(context, "/#join", 4));
        views.setOnClickPendingIntent(R.id.widget_host, EventWidget.open(context, "/#host", 5));
        return views;
    }
}
