package com.labwizard.lab_wizard

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat

class ConsumptionBuddyWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private fun renderFlaskieBitmap(context: Context, frameIndex: Int): Bitmap? {
            val resId = when (frameIndex % 3) {
                0 -> R.drawable.flaskie_frame_1
                1 -> R.drawable.flaskie_frame_2
                else -> R.drawable.flaskie_frame_3
            }
            return try {
                val drawable = ContextCompat.getDrawable(context, resId) ?: return null
                val density = context.resources.displayMetrics.density
                val width = (52 * density).toInt().coerceAtLeast(1)
                val height = (58 * density).toInt().coerceAtLeast(1)
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, width, height)
                drawable.draw(canvas)
                bitmap
            } catch (e: Throwable) {
                null
            }
        }

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_consumption_buddy)
                val prefs = context.getSharedPreferences("LabWizardWidgetPrefs", Context.MODE_PRIVATE)

                val labName = prefs.getString("lab_name", "Lab Wizard") ?: "Lab Wizard"
                views.setTextViewText(R.id.widget_lab_name, labName)

                val todayHeader = prefs.getString("today_header", "TODAY'S CONSUMPTION") ?: "TODAY'S CONSUMPTION"
                views.setTextViewText(R.id.widget_today_header, todayHeader)

                val flaskieSpeech = prefs.getString("flaskie_speech", "Ready to experiment!") ?: "Ready to experiment!"
                views.setTextViewText(R.id.widget_flaskie_bubble, flaskieSpeech)

                // Render dynamic Flaskie buddy into a parcelable Bitmap
                val frameIndex = prefs.getInt("flaskie_frame", 0)
                val flaskieBmp = renderFlaskieBitmap(context, frameIndex)
                if (flaskieBmp != null) {
                    views.setImageViewBitmap(R.id.widget_flaskie_image, flaskieBmp)
                }

                val item1Name = prefs.getString("item_1_name", "") ?: ""
                val item1Used = prefs.getString("item_1_used", "") ?: ""
                val item1Remaining = prefs.getString("item_1_remaining", "") ?: ""
                val item1Id = prefs.getString("item_1_id", "") ?: ""

                val item2Name = prefs.getString("item_2_name", "") ?: ""
                val item2Used = prefs.getString("item_2_used", "") ?: ""
                val item2Remaining = prefs.getString("item_2_remaining", "") ?: ""
                val item2Id = prefs.getString("item_2_id", "") ?: ""

                val item3Name = prefs.getString("item_3_name", "") ?: ""
                val item3Used = prefs.getString("item_3_used", "") ?: ""
                val item3Remaining = prefs.getString("item_3_remaining", "") ?: ""
                val item3Id = prefs.getString("item_3_id", "") ?: ""

                if (item1Name.isEmpty()) {
                    views.setViewVisibility(R.id.widget_items_container, View.GONE)
                    views.setViewVisibility(R.id.widget_empty_view, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_items_container, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_empty_view, View.GONE)

                    // Item 1
                    views.setTextViewText(R.id.widget_item_1_name, item1Name)
                    views.setTextViewText(R.id.widget_item_1_used, item1Used)
                    views.setTextViewText(R.id.widget_item_1_remaining, item1Remaining)
                    views.setViewVisibility(R.id.widget_item_1, View.VISIBLE)
                    if (item1Id.isNotEmpty()) {
                        views.setOnClickPendingIntent(
                            R.id.widget_item_1,
                            createDeepLinkIntent(context, "labwizard://item?id=$item1Id", 101)
                        )
                    }

                    // Item 2
                    if (item2Name.isNotEmpty()) {
                        views.setTextViewText(R.id.widget_item_2_name, item2Name)
                        views.setTextViewText(R.id.widget_item_2_used, item2Used)
                        views.setTextViewText(R.id.widget_item_2_remaining, item2Remaining)
                        views.setViewVisibility(R.id.widget_item_2, View.VISIBLE)
                        if (item2Id.isNotEmpty()) {
                            views.setOnClickPendingIntent(
                                R.id.widget_item_2,
                                createDeepLinkIntent(context, "labwizard://item?id=$item2Id", 102)
                            )
                        }
                    } else {
                        views.setViewVisibility(R.id.widget_item_2, View.GONE)
                    }

                    // Item 3
                    if (item3Name.isNotEmpty()) {
                        views.setTextViewText(R.id.widget_item_3_name, item3Name)
                        views.setTextViewText(R.id.widget_item_3_used, item3Used)
                        views.setTextViewText(R.id.widget_item_3_remaining, item3Remaining)
                        views.setViewVisibility(R.id.widget_item_3, View.VISIBLE)
                        if (item3Id.isNotEmpty()) {
                            views.setOnClickPendingIntent(
                                R.id.widget_item_3,
                                createDeepLinkIntent(context, "labwizard://item?id=$item3Id", 103)
                            )
                        }
                    } else {
                        views.setViewVisibility(R.id.widget_item_3, View.GONE)
                    }
                }

                // Pending Intents for Action Buttons
                views.setOnClickPendingIntent(
                    R.id.btn_widget_scan,
                    createDeepLinkIntent(context, "labwizard://scan_consume", 201)
                )
                views.setOnClickPendingIntent(
                    R.id.btn_widget_search,
                    createDeepLinkIntent(context, "labwizard://search", 202)
                )
                views.setOnClickPendingIntent(
                    R.id.btn_widget_undo,
                    createDeepLinkIntent(context, "labwizard://undo", 203)
                )
                views.setOnClickPendingIntent(
                    R.id.widget_flaskie_container,
                    createDeepLinkIntent(context, "labwizard://dashboard", 204)
                )
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    createDeepLinkIntent(context, "labwizard://dashboard", 205)
                )

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Throwable) {
                // Safeguard against inflation exceptions
            }
        }

        private fun createDeepLinkIntent(context: Context, uriString: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse(uriString)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            return PendingIntent.getActivity(context, requestCode, intent, flags)
        }
    }
}
