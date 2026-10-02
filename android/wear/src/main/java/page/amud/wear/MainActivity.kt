package page.amud.wear

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.widget.*
import android.content.Context
import com.google.android.gms.wearable.Wearable

class MainActivity : Activity() {
    private val refresh = android.os.Handler(android.os.Looper.getMainLooper())
    private var prayerKey: String? = null
    private val tick = object : Runnable { override fun run() { if (prayerKey == null) overview(); refresh.postDelayed(this, 30000) } }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        overview()
        Wearable.getDataClient(this).dataItems.addOnSuccessListener { items ->
            // Recover the retained Data Item when the watch is installed after
            // the phone's most recent sync, without waiting for another change.
            Thread {
                items.use { for (item in it) try { TimelineStore.receive(this, item) } catch (_: Exception) { } }
                runOnUiThread { if (prayerKey == null) overview() }
            }.start()
        }
    }
    override fun onResume() { super.onResume(); refresh.post(tick) }
    override fun onPause() { refresh.removeCallbacks(tick); super.onPause() }
    private fun column(): LinearLayout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL; setPadding(20, 30, 20, 36) }
    private fun text(value: String, size: Float = 17f) = TextView(this).apply { text = value; textSize = size; gravity = Gravity.CENTER; setPadding(0, 6, 0, 6) }
    private fun display(content: LinearLayout) { setContentView(ScrollView(this).apply { addView(content) }) }
    private fun overview() {
        val content = column()
        val entry = TimelineStore.active(this)
        content.addView(text(entry?.optString("hebrewDate") ?: "Open Amud on your phone", 21f))
        if (entry != null) {
            content.addView(text(entry.optString("parsha")))
            content.addView(text("${entry.optString("nextZman")}\n${entry.optString("nextZmanTime")}"))
            if (entry.optInt("omer") > 0) content.addView(text("Omer · ${entry.optInt("omer")}"))
        }
        val prayers = TimelineStore.prayers(this)
        for (i in 0 until prayers.length()) {
            val prayer = prayers.getJSONObject(i)
            content.addView(Button(this).apply { text = prayer.optString("title"); setOnClickListener { prayerKey = prayer.optString("key"); readPrayer(prayer) } })
        }
        display(content)
    }
    private fun readPrayer(prayer: org.json.JSONObject) {
        val content = column()
        content.addView(text(prayer.optString("hebrewTitle"), 22f))
        content.addView(text(prayer.optString("text"), 22f).apply { textDirection = android.view.View.TEXT_DIRECTION_RTL })
        content.addView(Button(this).apply { text = "Back"; setOnClickListener { prayerKey = null; overview() } })
        display(content)
    }
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() { if (prayerKey != null) { prayerKey = null; overview() } else super.onBackPressed() }
}
