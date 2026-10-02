package page.amud.wear

import androidx.wear.tiles.*
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

class AmudTileService : TileService() {
    override fun onTileRequest(params: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> {
        val entry = TimelineStore.active(this)
        val lines = if (entry == null) listOf("Amud", "Open the phone app to sync") else listOf(
            entry.optString("hebrewDate"), entry.optString("nextZman"), entry.optString("nextZmanTime"),
            if (entry.optInt("omer") > 0) "Omer · ${entry.optInt("omer")}" else "")
        val column = LayoutElementBuilders.Column.Builder()
        for (line in lines.filter { it.isNotEmpty() }) column.addContent(LayoutElementBuilders.Text.Builder().setText(line)
            .setFontStyle(LayoutElementBuilders.FontStyle.Builder().setSize(androidx.wear.protolayout.DimensionBuilders.sp(16f)).setColor(ColorBuilders.argb(0xFFFFFFFF.toInt())).build()).build())
        val layout = LayoutElementBuilders.Layout.Builder().setRoot(column.build()).build()
        val timeline = TimelineBuilders.Timeline.Builder().addTimelineEntry(TimelineBuilders.TimelineEntry.Builder().setLayout(layout).build()).build()
        return Futures.immediateFuture(TileBuilders.Tile.Builder().setResourcesVersion("1").setTileTimeline(timeline).setFreshnessIntervalMillis(60000).build())
    }
    override fun onTileResourcesRequest(params: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> =
        Futures.immediateFuture(ResourceBuilders.Resources.Builder().setVersion("1").build())
}
