package com.example.app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.ListView
import org.json.JSONObject

class HomeWidgetConfigureActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private lateinit var listView: ListView
    private lateinit var addButton: Button
    private lateinit var emptyView: View

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.widget_configure_layout)
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        listView = findViewById(R.id.widget_configure_list)
        addButton = findViewById(R.id.widget_configure_button)
        emptyView = findViewById(R.id.widget_configure_empty)

        val widgetData = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val trackerDataString = widgetData.getString("tracker_data", null)

        val listNames = if (trackerDataString != null) {
            try {
                val trackerData = JSONObject(trackerDataString)
                trackerData.keys().asSequence().toList()
            } catch (e: Exception) {
                emptyList<String>()
            }
        } else {
            emptyList<String>()
        }

        if (listNames.isEmpty()) {
            listView.visibility = View.GONE
            emptyView.visibility = View.VISIBLE
            addButton.isEnabled = false
        } else {
            listView.visibility = View.VISIBLE
            emptyView.visibility = View.GONE
            addButton.isEnabled = true

            val adapter = ArrayAdapter(this, android.R.layout.simple_list_item_single_choice, listNames)
            listView.adapter = adapter
            listView.choiceMode = ListView.CHOICE_MODE_SINGLE
        }

        addButton.setOnClickListener {
            val position = listView.checkedItemPosition
            if (position != ListView.INVALID_POSITION) {
                val selectedList = listNames[position]

                val newWidgetData = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                newWidgetData.edit()
                    .putString("selected_list_$appWidgetId", selectedList)
                    .apply()

                val appWidgetManager = AppWidgetManager.getInstance(this)
                HomeWidgetProvider().onUpdate(this, appWidgetManager, intArrayOf(appWidgetId))

                val resultValue = Intent()
                resultValue.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                setResult(RESULT_OK, resultValue)
                finish()
            }
        }
    }
}