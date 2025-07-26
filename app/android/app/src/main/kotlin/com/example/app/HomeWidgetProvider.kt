package com.example.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

class HomeWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.home_widget_layout)

            val selectedList = widgetData.getString("selected_list_$appWidgetId", null)
            views.setTextViewText(R.id.widget_title, selectedList ?: "Select a List")

            val trackerDataString = widgetData.getString("tracker_data", null)

            if (selectedList != null && trackerDataString != null) {
                try {
                    if (trackerDataString != null) {
                        val trackerData = JSONObject(trackerDataString)
                        val listData = trackerData.optJSONObject(selectedList)
                        if (listData != null) {
                            val heatmapBitmap = createHeatmapBitmap(listData.toString(), context)
                            views.setImageViewBitmap(R.id.widget_heatmap, heatmapBitmap)
                        }
                    }
                } catch (e: Exception) {
                    // Handle JSON parsing error if needed
                }
            }

            val launchIntent = Intent(context, MainActivity::class.java)
            val launchPendingIntent = PendingIntent.getActivity(context, appWidgetId, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_container, launchPendingIntent)

            views.setOnClickPendingIntent(R.id.widget_refresh_button, getRefreshPendingIntent(context, appWidgetId))

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE).edit().remove("selected_list_$appWidgetId").apply()
        }
    }

    private fun createHeatmapBitmap(data: String, context: Context): Bitmap {
        val width = 1000
        val height = 350
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint()

        paint.color = Color.TRANSPARENT
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)

        val workDataMap = parseWorkData(data)
        val today = LocalDate.now()
        val oneYearAgo = today.minusDays(365)
        val startDayOffset = oneYearAgo.dayOfWeek.value % 7
        val totalDays = ChronoUnit.DAYS.between(oneYearAgo, today) + 1 + startDayOffset
        val totalWeeks = (totalDays / 7.0).toInt()

        val cellSize = 20f
        val cellMargin = 4f

        for (weekIndex in 0 until totalWeeks) {
            for (dayIndex in 0..6) {
                val overallIndex = (weekIndex * 7) + dayIndex
                if (overallIndex < startDayOffset) continue

                val date = oneYearAgo.plusDays((overallIndex - startDayOffset).toLong())
                if (date.isAfter(today)) continue

                val dayData = workDataMap[date]
                paint.color = getColorForCategory(dayData?.optString("category"), context)

                val x = (totalWeeks - weekIndex - 1) * (cellSize + cellMargin)
                val y = dayIndex * (cellSize + cellMargin)
                canvas.drawRect(x, y, x + cellSize, y + cellSize, paint)
            }
        }
        return bitmap
    }

    private fun parseWorkData(data: String): Map<LocalDate, JSONObject> {
        val map = mutableMapOf<LocalDate, JSONObject>()
        val formatter = DateTimeFormatter.ofPattern("dd-MM-yyyy")
        try {
            val json = JSONObject(data)
            json.keys().forEach { dateStr ->
                try {
                    val date = LocalDate.parse(dateStr, formatter)
                    val activities = json.getJSONArray(dateStr)
                    if (activities.length() > 0) {
                        val firstActivity = activities.getJSONObject(0)
                        map[date] = firstActivity
                    }
                } catch (e: Exception) {
                    // Ignore malformed dates
                }
            }
        } catch (e: Exception) {
            // Ignore malformed json
        }
        return map
    }

    private fun getColorForCategory(category: String?, context: Context): Int {
        val isDark = (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES
        return when (category) {
            "Work" -> if (isDark) Color.parseColor("#5E5CE6") else Color.parseColor("#0066CC")
            "Health" -> Color.parseColor("#34C759")
            "Play" -> Color.parseColor("#FF9500")
            else -> if (isDark) Color.parseColor("#33FFFFFF") else Color.parseColor("#FFDDDDDD")
        }
    }

    private fun getRefreshPendingIntent(context: Context, appWidgetId: Int): PendingIntent {
        val intent = Intent(context, HomeWidgetProvider::class.java).apply {
            action = "android.appwidget.action.APPWIDGET_UPDATE"
            putExtra("appWidgetIds", intArrayOf(appWidgetId))
        }
        return PendingIntent.getBroadcast(context, appWidgetId, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}