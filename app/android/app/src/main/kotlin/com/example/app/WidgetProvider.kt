package com.example.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.os.Bundle
import android.widget.RemoteViews

/**
 * Generic receiver for the Flutter-rendered home-screen widget.
 *
 * Contains zero rendering logic: it only displays the PNG rendered by
 * `HomeWidget.renderFlutterWidget` (stored under `HomeWidgetPreferences`),
 * picks the size variant that best matches each widget instance, opens the
 * app on tap, and re-triggers an update on refresh.
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
        for (appWidgetId in appWidgetIds) {
            updateOne(context, appWidgetManager, prefs, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        val prefs = context.getSharedPreferences(
            "HomeWidgetPreferences",
            Context.MODE_PRIVATE
        )
        updateOne(context, appWidgetManager, prefs, appWidgetId)
    }

    private fun updateOne(
        context: Context,
        appWidgetManager: AppWidgetManager,
        prefs: android.content.SharedPreferences,
        appWidgetId: Int
    ) {
        val isNight =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
        val suffix = if (isNight) "_dark" else ""
        val variant = sizeVariantFor(appWidgetManager, appWidgetId)
        val imagePath = prefs.getString("widget_image_${variant}$suffix", null)

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

    /**
     * Maps the launcher-granted min width (dp) to a rendered PNG variant.
     * Buckets: <= 180dp -> small (2x2), <= 280dp -> medium (4x2), else large.
     */
    private fun sizeVariantFor(
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ): String {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val minWidthDp = options.getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,
            0
        )
        return when {
            minWidthDp in 1..180 -> "small"
            minWidthDp in 181..280 -> "medium"
            else -> "large"
        }
    }
}
