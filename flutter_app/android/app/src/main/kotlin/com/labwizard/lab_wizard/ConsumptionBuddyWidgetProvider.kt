package com.labwizard.lab_wizard

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat

class ConsumptionBuddyWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_FLASKIE_TAP) {
            animateFlaskieBurst(context)
        }
    }

    private fun animateFlaskieBurst(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val ids = appWidgetManager.getAppWidgetIds(
            ComponentName(context, ConsumptionBuddyWidgetProvider::class.java)
        )
        if (ids == null || ids.isEmpty()) return

        val prefs = context.getSharedPreferences("LabWizardWidgetPrefs", Context.MODE_PRIVATE)
        val baseSpeech = prefs.getString("flaskie_speech", "Ready to experiment!") ?: "Ready to experiment!"
        val baseFrame = prefs.getInt("flaskie_frame", 0)
        val quotes = arrayOf("Bubbles rising! ✨", "Safety goggles check! 🥽", "Pop! Ready to log! 🧪")

        val pendingResult = goAsync()
        val handler = Handler(Looper.getMainLooper())

        // Frame 0: Bubble rising
        val views0 = RemoteViews(context.packageName, R.layout.widget_consumption_buddy)
        renderFlaskieBitmap(context, 0)?.let { views0.setImageViewBitmap(R.id.widget_flaskie_image, it) }
        views0.setTextViewText(R.id.widget_flaskie_bubble, quotes[0])
        for (id in ids) appWidgetManager.partiallyUpdateAppWidget(id, views0)

        // Frame 1: Wink / Blink after 320ms
        handler.postDelayed({
            val views1 = RemoteViews(context.packageName, R.layout.widget_consumption_buddy)
            renderFlaskieBitmap(context, 1)?.let { views1.setImageViewBitmap(R.id.widget_flaskie_image, it) }
            views1.setTextViewText(R.id.widget_flaskie_bubble, quotes[1])
            for (id in ids) appWidgetManager.partiallyUpdateAppWidget(id, views1)
        }, 320)

        // Frame 2: Joyful bubble pop after 640ms
        handler.postDelayed({
            val views2 = RemoteViews(context.packageName, R.layout.widget_consumption_buddy)
            renderFlaskieBitmap(context, 2)?.let { views2.setImageViewBitmap(R.id.widget_flaskie_image, it) }
            views2.setTextViewText(R.id.widget_flaskie_bubble, quotes[2])
            for (id in ids) appWidgetManager.partiallyUpdateAppWidget(id, views2)
        }, 640)

        // Reset to lab status after 1200ms
        handler.postDelayed({
            val viewsRestore = RemoteViews(context.packageName, R.layout.widget_consumption_buddy)
            renderFlaskieBitmap(context, baseFrame)?.let { viewsRestore.setImageViewBitmap(R.id.widget_flaskie_image, it) }
            viewsRestore.setTextViewText(R.id.widget_flaskie_bubble, baseSpeech)
            for (id in ids) appWidgetManager.partiallyUpdateAppWidget(id, viewsRestore)
            pendingResult.finish()
        }, 1200)
    }

    companion object {
        const val ACTION_FLASKIE_TAP = "com.labwizard.lab_wizard.ACTION_FLASKIE_TAP"

        fun renderFlaskieBitmap(context: Context, frameIndex: Int): Bitmap? {
            val resId = when (frameIndex % 3) {
                0 -> R.drawable.flaskie_frame_1
                1 -> R.drawable.flaskie_frame_2
                else -> R.drawable.flaskie_frame_3
            }
            return try {
                val drawable = ContextCompat.getDrawable(context, resId) ?: return null
                val density = context.resources.displayMetrics.density
                val width = (60 * density).toInt().coerceAtLeast(1)
                val height = (66 * density).toInt().coerceAtLeast(1)
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
                            createLaunchIntent(context, "labwizard://item?id=$item1Id", 101)
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
                                createLaunchIntent(context, "labwizard://item?id=$item2Id", 102)
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
                                createLaunchIntent(context, "labwizard://item?id=$item3Id", 103)
                            )
                        }
                    } else {
                        views.setViewVisibility(R.id.widget_item_3, View.GONE)
                    }
                }

                // Benchtop Action Buttons
                views.setOnClickPendingIntent(
                    R.id.btn_widget_scan,
                    createLaunchIntent(context, "labwizard://scan_consume", 201)
                )
                views.setOnClickPendingIntent(
                    R.id.btn_widget_search,
                    createLaunchIntent(context, "labwizard://search", 202)
                )
                views.setOnClickPendingIntent(
                    R.id.btn_widget_undo,
                    createLaunchIntent(context, "labwizard://undo", 203)
                )

                // Interactive Flaskie Buddy Tap Animation
                views.setOnClickPendingIntent(
                    R.id.widget_flaskie_image,
                    createFlaskieTapIntent(context)
                )

                // Speech Bubble & Card Background open app dashboard
                views.setOnClickPendingIntent(
                    R.id.widget_flaskie_bubble,
                    createLaunchIntent(context, "labwizard://dashboard", 204)
                )
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    createLaunchIntent(context, "labwizard://dashboard", 205)
                )

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Throwable) {
                // Safeguard against unhandled exceptions
            }
        }

        private fun createLaunchIntent(context: Context, uriString: String, requestCode: Int): PendingIntent {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val intent = (launchIntent ?: Intent(context, MainActivity::class.java)).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse(uriString)
                putExtra("deep_link_uri", uriString)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            return PendingIntent.getActivity(context, requestCode, intent, flags)
        }

        private fun createFlaskieTapIntent(context: Context): PendingIntent {
            val intent = Intent(context, ConsumptionBuddyWidgetProvider::class.java).apply {
                action = ACTION_FLASKIE_TAP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            return PendingIntent.getBroadcast(context, 301, intent, flags)
        }
    }
}
