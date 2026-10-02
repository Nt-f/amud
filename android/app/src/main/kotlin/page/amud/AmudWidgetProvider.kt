package page.amud

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

class AmudWidgetProvider : HomeWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == REFRESH || intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_TIME_CHANGED || intent.action == Intent.ACTION_TIMEZONE_CHANGED) {
            val manager = AppWidgetManager.getInstance(context)
            onUpdate(context, manager, manager.getAppWidgetIds(android.content.ComponentName(context, javaClass)))
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, data: SharedPreferences) {
        val now = System.currentTimeMillis()
        var nextRefresh = now + 30 * 60 * 1000
        val timeline = try { JSONObject(data.getString("amudTimeline", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
        var active: JSONObject? = null
        if (timeline.optLong("validUntil") > now) {
            val entries = timeline.optJSONArray("entries")
            for (i in 0 until (entries?.length() ?: 0)) {
                val entry = entries!!.getJSONObject(i)
                if (entry.optLong("at") <= now) active = entry
                else { nextRefresh = minOf(nextRefresh, entry.optLong("at")); break }
            }
            nextRefresh = minOf(nextRefresh, timeline.optLong("validUntil"))
        }
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.amud_widget)
            views.setTextViewText(R.id.widget_date, active?.optString("hebrewDate") ?: "Amud")
            views.setTextViewText(R.id.widget_parsha, active?.optString("parsha") ?: "Open Amud to refresh")
            views.setTextViewText(R.id.widget_zman, active?.let { "${it.optString("nextZman")} ${it.optString("nextZmanTime")}" } ?: "")
            val omer = active?.optInt("omer") ?: 0
            views.setTextViewText(R.id.widget_omer, if (omer > 0) "Omer · $omer" else "")
            views.setTextViewText(R.id.widget_candles, active?.optString("candleLighting")?.takeIf { it.isNotEmpty() }?.let { "🕯 $it" } ?: "")
            views.setTextViewText(R.id.widget_location, timeline.optString("location"))
            fun open(route: String, request: Int): PendingIntent {
                val intent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW; setData(Uri.parse("amud://$route"))
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                return PendingIntent.getActivity(context, request, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            }
            views.setOnClickPendingIntent(R.id.widget_root, open("zmanim", id * 10))
            views.setOnClickPendingIntent(R.id.widget_omer, open("pray/omer", id * 10 + 1))
            manager.updateAppWidget(id, views)
        }
        if (ids.isNotEmpty()) {
            val intent = Intent(context, AmudWidgetProvider::class.java).setAction(REFRESH)
            val pending = PendingIntent.getBroadcast(context, 410, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) alarm.setAndAllowWhileIdle(AlarmManager.RTC, nextRefresh, pending)
            else alarm.set(AlarmManager.RTC, nextRefresh, pending)
        }
    }
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        val pending = PendingIntent.getBroadcast(context, 410, Intent(context, AmudWidgetProvider::class.java).setAction(REFRESH), PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
        if (pending != null) (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending)
    }
    companion object { const val REFRESH = "page.amud.WIDGET_REFRESH" }
}
