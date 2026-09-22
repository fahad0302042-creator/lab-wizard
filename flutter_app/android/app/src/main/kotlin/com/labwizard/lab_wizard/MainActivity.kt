package com.labwizard.lab_wizard

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.labwizard.lab_wizard/widget"
    private var initialUri: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val data = call.arguments as? Map<*, *>
                    if (data != null) {
                        saveWidgetData(data)
                        updateAppWidget()
                    }
                    result.success(true)
                }
                "getInitialUri" -> {
                    result.success(initialUri)
                    initialUri = null
                }
                "clearWidget" -> {
                    clearWidgetData()
                    updateAppWidget()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractUri(intent)?.let { uri ->
            initialUri = uri
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractUri(intent)?.let { uri ->
            initialUri = uri
            flutterEngine?.let { engine ->
                try {
                    MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
                        .invokeMethod("onDeepLink", uri)
                } catch (e: Throwable) {
                    // Flutter will fetch initialUri on startup
                }
            }
        }
    }

    /**
     * Widget taps carry a token that only this app can put in the
     * PendingIntent (it lives in private prefs). A browsable `labwizard://`
     * link, or another app starting this activity, does not have it, so it
     * cannot undo stock or open an item.
     */
    private fun extractUri(intent: Intent?): String? {
        if (intent == null) return null
        val token = intent.getStringExtra(ConsumptionBuddyWidgetProvider.LAUNCH_TOKEN)
        val expected = getSharedPreferences(
            ConsumptionBuddyWidgetProvider.PREFS_NAME,
            Context.MODE_PRIVATE,
        ).getString(ConsumptionBuddyWidgetProvider.LAUNCH_TOKEN, null)
        if (token.isNullOrEmpty() || expected.isNullOrEmpty() || token != expected) {
            return null
        }
        val extraUri = intent.getStringExtra("deep_link_uri")
        if (extraUri != null && extraUri.startsWith("labwizard://")) {
            return extraUri
        }
        val dataUri = intent.data?.toString()
        if (dataUri != null && dataUri.startsWith("labwizard://")) {
            return dataUri
        }
        return null
    }

    private fun clearWidgetData() {
        getSharedPreferences(ConsumptionBuddyWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }

    private fun saveWidgetData(data: Map<*, *>) {
        val prefs = getSharedPreferences("LabWizardWidgetPrefs", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        for ((key, value) in data) {
            if (key !is String) continue
            when (value) {
                is String -> editor.putString(key, value)
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
                is Float -> editor.putFloat(key, value)
                is Double -> editor.putFloat(key, value.toFloat())
                is Boolean -> editor.putBoolean(key, value)
            }
        }
        editor.apply()
    }

    private fun updateAppWidget() {
        val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
        val ids = appWidgetManager.getAppWidgetIds(
            ComponentName(applicationContext, ConsumptionBuddyWidgetProvider::class.java)
        )
        if (ids != null && ids.isNotEmpty()) {
            for (id in ids) {
                ConsumptionBuddyWidgetProvider.updateAppWidget(applicationContext, appWidgetManager, id)
            }
        }
    }
}
