package page.amud

import android.app.Activity
import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.view.Surface
import io.flutter.plugin.common.EventChannel

/// The way the phone faces, for the reader's compass: degrees from true
/// north of the screen's top when it lies flat, and of its back when held
/// upright (in between, the two blend into "straight ahead"). Listening
/// takes `{lat, lon, alt}` for the magnetic declination there.
class HeadingStream(private val activity: Activity) : EventChannel.StreamHandler, SensorEventListener {
    private val sensors = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var sink: EventChannel.EventSink? = null
    private var declination = 0f
    private var calibrate = false
    private val matrix = FloatArray(9)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val sensor = sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (sensor == null) {
            events.error("unavailable", "No compass on this device", null)
            events.endOfStream()
            return
        }
        val at = arguments as? Map<*, *>
        val lat = (at?.get("lat") as? Number)?.toFloat()
        val lon = (at?.get("lon") as? Number)?.toFloat()
        val alt = (at?.get("alt") as? Number)?.toFloat() ?: 0f
        declination = if (lat != null && lon != null) GeomagneticField(lat, lon, alt, System.currentTimeMillis()).declination else 0f
        sink = events
        sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        sensors.unregisterListener(this)
        sink = null
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        calibrate = accuracy <= SensorManager.SENSOR_STATUS_ACCURACY_LOW
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sink = sink ?: return
        SensorManager.getRotationMatrixFromVector(matrix, event.values)
        // Columns of the matrix are the phone's axes in east/north/up.
        // Screen-up and screen-back depend on how the display is turned.
        @Suppress("DEPRECATION")
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) activity.display?.rotation ?: Surface.ROTATION_0
            else activity.windowManager.defaultDisplay.rotation
        val (upE, upN) = when (rotation) {
            Surface.ROTATION_90 -> matrix[0] to matrix[3]
            Surface.ROTATION_180 -> -matrix[1] to -matrix[4]
            Surface.ROTATION_270 -> -matrix[0] to -matrix[3]
            else -> matrix[1] to matrix[4]
        }
        val east = upE - matrix[2]
        val north = upN - matrix[5]
        if (east * east + north * north < 1e-4f) return
        val heading = (Math.toDegrees(kotlin.math.atan2(east, north).toDouble()) + declination + 360) % 360
        sink.success(mapOf("heading" to heading, "calibrate" to calibrate))
    }
}
