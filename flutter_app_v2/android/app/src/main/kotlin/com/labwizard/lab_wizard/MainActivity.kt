package com.labwizard.lab_wizard

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lab_wizard/timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "localTimeZone") {
                    result.success(TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }
    }
}
