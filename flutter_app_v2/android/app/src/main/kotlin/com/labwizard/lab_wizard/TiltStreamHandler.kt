package com.labwizard.lab_wizard

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * The phone's tilt, broadcast to Flutter.
 *
 * Why this exists: Flutter's SDK has no sensor API, and every pub package that
 * wraps one would be a new dependency in a project that has stayed deliberately
 * dependency-light. Tilt is the app's signature interaction, so it gets a
 * twenty-line platform channel instead of a package that has to be audited,
 * upgraded and kept working across Flutter majors.
 *
 * Nothing is sampled until Flutter opens the stream, so a build with tilt off
 * and the app in the background costs no battery at all.
 *
 * The numbers sent are the device's attitude in degrees, not raw accelerometer
 * values, because the UI wants "how far is the phone tipped" and should not
 * have to re-derive soft-iron corrections on the Dart side:
 *
 *  - `roll`  — rotation about the long axis, -180..180. Tipping the phone's top
 *              away from you right-handed gives a positive roll.
 *  - `pitch` — rotation about the short axis, -90..90.
 *  - `flat`  — true when the phone is close enough to horizontal that the
 *              sensor's reading would be noise, so the UI can settle instead of
 *              jittering.
 *
 * A low-pass filter runs here rather than in Dart: sensor noise arrives at the
 * full sample rate, and smoothing it before it crosses the channel keeps the
 * main isolate off the hot path.
 */
class TiltStreamHandler(private val context: Context) : EventChannel.StreamHandler,
    SensorEventListener {

    private var events: EventChannel.EventSink? = null
    private val sensors: SensorManager? =
        context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

    /** Rotation vector: already fused, so no accelerometer-plus-magnetometer maths. */
    private val sensor: Sensor? =
        sensors?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensors?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            ?: sensors?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private val main = Handler(Looper.getMainLooper())
    private var lastSent = 0L

    // Filter state, in degrees. Seeded on the first reading so the liquid does
    // not snap from flat to wherever the phone happens to be held.
    private var smoothRoll = Float.NaN
    private var smoothPitch = Float.NaN

    private val rotation = FloatArray(9)
    private val orientation = FloatArray(3)

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        val manager = sensors
        val target = sensor
        if (manager == null || target == null) {
            // No sensor: say so once, then stay silent. The Dart side falls back
            // to drag, which is a complete interaction on its own.
            sink?.success(
                mapOf(
                    "roll" to 0.0,
                    "pitch" to 0.0,
                    "flat" to true,
                    "supported" to false
                )
            )
            return
        }
        sink?.success(
            mapOf(
                "roll" to 0.0,
                "pitch" to 0.0,
                "flat" to true,
                "supported" to true
            )
        )
        // SENSOR_DELAY_GAME (~50 Hz) is the right rate for an animation: faster
        // than the eye, slower than the battery-draining default of "as fast as
        // possible".
        manager.registerListener(this, target, SensorManager.SENSOR_DELAY_GAME)
    }

    override fun onCancel(arguments: Any?) {
        sensors?.unregisterListener(this)
        events = null
        smoothRoll = Float.NaN
        smoothPitch = Float.NaN
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onSensorChanged(event: SensorEvent) {
        val manager = sensors ?: return
        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            // Fallback path: derive roll/pitch straight from gravity. No
            // magnetometer, so the reading is unaffected by nearby steel
            // shelving — which a store room is full of.
            val gx = event.values[0]
            val gy = event.values[1]
            val gz = event.values[2]
            val norm = kotlin.math.sqrt(gx * gx + gy * gy + gz * gz)
            if (norm < 1f) return
            val rollDeg = Math.toDegrees(
                kotlin.math.atan2(gy.toDouble(), gz.toDouble())
            ).toFloat()
            val pitchDeg = Math.toDegrees(
                kotlin.math.asin((-gx / norm).coerceIn(-1f, 1f).toDouble())
            ).toFloat()
            emit(rollDeg, pitchDeg)
            return
        }

        SensorManager.getRotationMatrixFromVector(rotation, event.values)
        SensorManager.getOrientation(rotation, orientation)
        // orientation is radians: azimuth, pitch, roll.
        val pitchDeg = Math.toDegrees(orientation[1].toDouble()).toFloat()
        val rollDeg = Math.toDegrees(orientation[2].toDouble()).toFloat()
        emit(rollDeg, pitchDeg)
    }

    private fun emit(rawRoll: Float, rawPitch: Float) {
        // 12% new per sample at ~50 Hz settles in about a tenth of a second:
        // smooth enough to read as liquid, quick enough to feel connected.
        val alpha = .12f
        smoothRoll = if (smoothRoll.isNaN()) rawRoll
        else smoothRoll + (rawRoll - smoothRoll) * alpha
        smoothPitch = if (smoothPitch.isNaN()) rawPitch
        else smoothPitch + (rawPitch - smoothPitch) * alpha

        // Cap the outbound rate at ~30 Hz. Anything the display cannot show is
        // channel traffic and repaint work for nothing.
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastSent < 33) return
        lastSent = now

        val payload = mapOf(
            "roll" to smoothRoll.toDouble(),
            "pitch" to smoothPitch.toDouble(),
            "flat" to (kotlin.math.abs(smoothPitch) < 6f &&
                kotlin.math.abs(smoothRoll) < 6f),
            "supported" to true
        )
        main.post { events?.success(payload) }
    }
}
