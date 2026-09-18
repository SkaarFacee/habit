package com.example.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.widget.RemoteViews

/**
 * Generic receiver for the Flutter-rendered home-screen widget.
 *
 * Contains zero logic: it only displays the PNG rendered by
 * `HomeWidget.renderFlutterWidget` (stored under `HomeWidgetPreferences`),
 * opens the app on tap, and re-triggers an update on refresh.
 */
class WidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences(
            "HomeWidgetPreferences",
            Context.MODE_PRIVATE
        )
        val isNight =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
        val imagePath = prefs.getString(
            if (isNight) "widget_image_dark" else "widget_image",
            null
        )

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                val bitmap = imagePath?.let { BitmapFactory.decodeFile(it) }
                if (bitmap != null) {
                    setImageViewBitmap(R.id.widget_image, bitmap)
                }

                val openApp = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_image, openApp)
                setContentDescription(
                    R.id.widget_image,
                    context.getString(R.string.app_name)
                )

                val refresh = PendingIntent.getBroadcast(
                    context,
                    appWidgetId,
                    Intent(context, WidgetProvider::class.java).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        putExtra(
                            AppWidgetManager.EXTRA_APPWIDGET_IDS,
                            intArrayOf(appWidgetId)
                        )
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_refresh, refresh)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}