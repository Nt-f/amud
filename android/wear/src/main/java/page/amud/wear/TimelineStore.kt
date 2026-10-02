package page.amud.wear

import android.content.Context
import org.json.JSONObject
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import android.content.ComponentName
import com.google.android.gms.wearable.*
import com.google.android.gms.tasks.Tasks

object TimelineStore {
    fun read(context: Context): JSONObject = try {
        JSONObject(context.getSharedPreferences("amud", Context.MODE_PRIVATE).getString("timeline", "{}") ?: "{}")
    } catch (_: Exception) { JSONObject() }

    fun active(context: Context): JSONObject? {
        val data = read(context)
        val now = System.currentTimeMillis()
        if (data.optLong("validUntil") <= now) return null
        val entries = data.optJSONArray("entries") ?: return null
        var current: JSONObject? = null
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i)
            if (entry.optLong("at") > now) break
            current = entry
        }
        return current
    }

    fun prayers(context: Context): org.json.JSONArray {
        val active = active(context) ?: return org.json.JSONArray()
        val days = read(context).optJSONArray("prayerDays") ?: return org.json.JSONArray()
        for (i in 0 until days.length()) {
            val day = days.getJSONObject(i)
            if (day.optInt("day") == active.optInt("prayerDay")) return day.optJSONArray("prayers") ?: org.json.JSONArray()
        }
        return org.json.JSONArray()
    }

    fun save(context: Context, json: String) {
        val parsed = JSONObject(json)
        if (parsed.optInt("version") != 1) return
        context.getSharedPreferences("amud", Context.MODE_PRIVATE).edit().putString("timeline", json).apply()
        TileService.getUpdater(context).requestUpdate(AmudTileService::class.java)
        for (provider in listOf(NextZmanComplication::class.java, OmerComplication::class.java)) {
            ComplicationDataSourceUpdateRequester.create(context, ComponentName(context, provider)).requestUpdateAll()
        }
    }

    fun receive(context: Context, item: DataItem) {
        if (item.uri.path != "/amud/timeline") return
        val asset = DataMapItem.fromDataItem(item).dataMap.getAsset("timeline") ?: return
        val response = Tasks.await(Wearable.getDataClient(context).getFdForAsset(asset))
        response.inputStream?.use { stream ->
            val bytes = stream.readBytes()
            if (bytes.size <= 1024 * 1024) save(context, bytes.toString(Charsets.UTF_8))
        }
    }
}
class TimelineListener : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) if (event.type == DataEvent.TYPE_CHANGED) {
            try { TimelineStore.receive(this, event.dataItem) } catch (_: Exception) { }
        }
    }
}
