package page.amud.appfunctions

import android.content.Context
import androidx.annotation.RequiresApi
import androidx.appfunctions.AppFunctionElementNotFoundException
import androidx.appfunctions.AppFunctionSerializable
import androidx.appfunctions.service.AppFunction
import androidx.appfunctions.service.AppFunctionService
import androidx.appfunctions.service.AppFunctionServiceEntryPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** An answer an assistant can read out loud. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class AmudAnswer(
    /** What the answer is about, such as "Sunset" or "Parsha". */
    val title: String,
    /** The value alone, such as "6:21 PM" or "Parashat Noach". */
    val value: String,
    /** A complete sentence that can be read aloud as it is. */
    val spoken: String,
    /** The place the times were worked out for, such as "New York". */
    val location: String,
)

/**
 * What Amud, a Jewish prayer book and halachic times app, tells assistants.
 * Everything is read from the times Amud last worked out for the user's own
 * saved location, so it is private, instant and needs no network. If Amud
 * hasn't been opened for about a week the answers are missing, and the
 * assistant should ask the user to open Amud once.
 */
@RequiresApi(36)
@AppFunctionServiceEntryPoint(
    serviceName = "AmudAppFunctionService",
    appFunctionXmlFileName = "amud_app_function_service",
)
abstract class BaseAmudAppFunctionService : AppFunctionService() {

    /**
     * Gets the next halachic time (zman) that has not passed yet, such as
     * "Sof Zman Shema", "Chatzos" or "Sunset", with its time today in the
     * user's saved location.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getNextZman(): AmudAnswer = answer { e, place ->
        val name = e.optString("nextZman")
        val time = e.optString("nextZmanTime")
        require(name.isNotEmpty()) { "No upcoming zman" }
        AmudAnswer(name, time, "The next time is $name at $time.", place)
    }

    /**
     * Gets today's Hebrew date, for example "29 Tishrei 5787". After sunset it
     * already gives the next day's date, as the Jewish day begins at nightfall.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getHebrewDate(): AmudAnswer = answer { e, place ->
        val date = e.optString("dateLabel").ifEmpty { e.optString("hebrewDate") }
        AmudAnswer("Hebrew date", date, "Today is $date.", place)
    }

    /** Gets this week's Torah portion (parsha), or the coming Shabbat's. */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getParsha(): AmudAnswer = answer { e, place ->
        val parsha = e.optString("parsha")
        AmudAnswer("Parsha", parsha, "This week's Torah portion is $parsha.", place)
    }

    /**
     * Gets today's count of the Omer (Sefirat HaOmer), from the second night
     * of Pesach to Shavuot. Outside those 49 days it says there is no count.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getOmerCount(): AmudAnswer = answer { e, place ->
        val day = e.optInt("omer")
        if (day > 0) AmudAnswer("Omer", "$day", "Today is day $day of the Omer.", place)
        else AmudAnswer("Omer", "", "There is no Omer count right now.", place)
    }

    /**
     * Gets the next Shabbat or Yom Tov candle lighting time in the user's
     * saved location, or says there is none in the coming days.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getCandleLighting(): AmudAnswer = answer { e, place ->
        val candles = e.optString("candleLighting")
        if (candles.isNotEmpty()) AmudAnswer("Candle lighting", candles, "Candle lighting is $candles.", place)
        else AmudAnswer("Candle lighting", "", "There is no candle lighting in the next few days.", place)
    }

    /** Gets the next sunrise (netz hachama) time in the user's saved location. */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getSunrise(): AmudAnswer = answer { e, place ->
        val time = e.optString("sunriseTime")
        require(time.isNotEmpty()) { "No sunrise time" }
        AmudAnswer("Sunrise", time, "Sunrise is at $time.", place)
    }

    /** Gets the next sunset (shkia) time in the user's saved location. */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getSunset(): AmudAnswer = answer { e, place ->
        val time = e.optString("sunsetTime")
        require(time.isNotEmpty()) { "No sunset time" }
        AmudAnswer("Sunset", time, "Sunset is at $time.", place)
    }

    private suspend fun answer(build: (JSONObject, String) -> AmudAnswer): AmudAnswer =
        withContext(Dispatchers.IO) {
            val (entry, place) = TimelineReader.active(applicationContext)
                ?: throw AppFunctionElementNotFoundException("Amud has no up-to-date times. Ask the user to open Amud once.")
            try {
                build(entry, place)
            } catch (e: IllegalArgumentException) {
                throw AppFunctionElementNotFoundException(e.message ?: "Not available")
            }
        }
}

/** The eight-day timeline the app publishes for its widgets (see widget_snapshot.dart). */
internal object TimelineReader {
    fun active(context: Context, now: Long = System.currentTimeMillis()): Pair<JSONObject, String>? {
        val raw = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE).getString("amudTimeline", null)
            ?: return null
        val timeline = try { JSONObject(raw) } catch (_: Exception) { return null }
        if (timeline.optLong("validUntil") <= now) return null
        val entries = timeline.optJSONArray("entries") ?: return null
        var active: JSONObject? = null
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i)
            if (entry.optLong("at") > now) break
            active = entry
        }
        return active?.let { it to timeline.optString("location") }
    }
}
