package page.amud.wear

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.*
import androidx.wear.watchface.complications.datasource.*

abstract class AmudComplication : ComplicationDataSourceService() {
    abstract val omer: Boolean
    private fun data(type: ComplicationType, preview: Boolean): ComplicationData? {
        val entry = TimelineStore.active(this)
        val text = if (preview) { if (omer) "18" else "8:30" } else if (entry == null) "Sync" else
            if (omer) entry.optInt("omer").let { if (it > 0) "$it" else "—" } else entry.optString("nextZmanTime")
        val title = if (omer) "Omer" else if (preview) "Shema" else entry?.optString("nextZman") ?: "Amud"
        val action = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val description = PlainComplicationText.Builder("$title $text").build()
        return when (type) {
            ComplicationType.SHORT_TEXT -> ShortTextComplicationData.Builder(PlainComplicationText.Builder(text.take(7)).build(), description)
                .setTitle(PlainComplicationText.Builder(title.take(7)).build()).setTapAction(action).build()
            ComplicationType.LONG_TEXT -> LongTextComplicationData.Builder(description, description).setTapAction(action).build()
            else -> null
        }
    }
    override fun onComplicationRequest(request: ComplicationRequest, listener: ComplicationRequestListener) {
        listener.onComplicationData(data(request.complicationType, false))
    }
    override fun getPreviewData(type: ComplicationType): ComplicationData? = data(type, true)
}
class NextZmanComplication : AmudComplication() { override val omer = false }
class OmerComplication : AmudComplication() { override val omer = true }
