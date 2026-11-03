package tipsapp.core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import tipsapp.core.model.MatchDay
import tipsapp.core.model.SourceReport
import java.time.LocalDate
import java.time.OffsetDateTime

/**
 * Samlar dagens matcher från alla källor. Om en källa fallerar fortsätter de andra,
 * och felet syns i [MatchDay.sources].
 */
class DailyFetcher(
    private val sources: List<MatchSource>,
    private val enrichers: List<MatchEnricher> = emptyList(),
) {
    fun fetch(date: LocalDate): MatchDay {
        val reports = mutableListOf<SourceReport>()
        val all = sources.flatMap { src ->
            try {
                val r = src.fetch(date)
                val msg = (r.extra + r.warnings).joinToString("; ").ifBlank { null }
                reports += SourceReport(src.name, true, r.matches.size, r.callsUsed, msg)
                r.matches
            } catch (e: Exception) {
                reports += SourceReport(src.name, false, 0, message = "${e::class.simpleName}: ${e.message}")
                emptyList()
            }
        }
        var matches = all
        for (en in enrichers) {
            try {
                val (updated, msg) = en.enrich(matches, date)
                matches = updated
                reports += SourceReport(en.name, true, 0, message = msg)
            } catch (e: Exception) {
                reports += SourceReport(en.name, false, 0, message = "${e::class.simpleName}: ${e.message}")
            }
        }
        return MatchDay(
            date = date.toString(),
            generatedAt = OffsetDateTime.now().toString(),
            matches = matches.sortedWith(compareBy({ it.kickoff }, { it.league.name })),
            sources = reports,
        )
    }

    companion object {
        val json = Json { prettyPrint = true; encodeDefaults = false; explicitNulls = false }
        fun toJson(day: MatchDay): String = json.encodeToString(day)
    }
}
