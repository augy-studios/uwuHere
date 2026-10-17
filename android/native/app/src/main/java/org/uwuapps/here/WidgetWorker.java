/*
 * The "Your event" widget's refresh every 15 minutes (WidgetData.schedule), so check-ins by
 * location and early leavers show with the app closed. Runs only while a widget is on the home
 * screen and its event is still on, and stops itself otherwise. WorkManager keeps it through
 * restarts and updates by itself.
 */
package org.uwuapps.here;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

public class WidgetWorker extends Worker {
    public WidgetWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    @NonNull
    @Override
    public Result doWork() {
        Context context = getApplicationContext();
        if (WidgetData.needed(context)) {
            WidgetData.refresh(context);
            EventWidget.drawAll(context, false);
        }
        // An event that has just ended, or gone, needs no more.
        WidgetData.schedule(context);
        return Result.success();
    }
}
