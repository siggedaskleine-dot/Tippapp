package tipsapp.core.kambi

import kotlinx.serialization.json.JsonElement
import tipsapp.core.MatchEnricher
import tipsapp.core.MatchSource
import tipsapp.core.SourceResult
import tipsapp.core.http.*
import tipsapp.core.model.*
import tipsapp.core.util.TeamMatcher
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId

data class KambiEvent(
    val id: String,
    val home: String,
    val away: String,
    val start: OffsetDateTime?,
    val group: String,
    val pathKeys: List<String>,
    val markets: List<OddsMarket>,
)

/**
 * Hockeyodds från Kambis öppna oddsflöde (samma som Unibet använder). Ingen nyckel krävs.
 * Täcker SHL, Hockeyallsvenskan och NHL.
 */
class KambiHockey(
    private val http: JsonHttp = JsonHttp(),
    private val cache: ResponseCache = MemoryCache(),
    private val baseUrl: String = "https://eu-offering-api.kambicdn.com/offering/v2018/ub",
) {
    var calls = 0
        private set

    fun events(): List<KambiEvent> {
        val path = "listView/ice_hockey/all/all/all/matches.json"
        val key = "kambi:$path"
        val json = cache.get(key, 10 * 60_000L) ?: http.get(
            baseUrl, path, mapOf("lang" to "sv_SE", "market" to "SE", "useCombined" to "true"),
        ).body.also { calls++; cache.put(key, it) }
        return parse(json)
    }

    companion object {
        fun parse(json: JsonElement): List<KambiEvent> = json["events"].arr().mapNotNull { row ->
            val ev = row["event"] ?: return@mapNotNull null
            val home = ev["homeName"].str() ?: return@mapNotNull null
            val away = ev["awayName"].str() ?: return@mapNotNull null
            KambiEvent(
                id = ev["id"].str() ?: "?",
                home = home, away = away,
                start = ev["start"].str()?.let { runCatching { OffsetDateTime.parse(it) }.getOrNull() },
                group = ev["group"].str() ?: "",
                pathKeys = ev["path"].arr().mapNotNull { it["termKey"].str()?.lowercase() ?: it["englishName"].str()?.lowercase() },
                markets = row["betOffers"].arr().mapNotNull { parseOffer(it) },
            )
        }

        private fun parseOffer(bo: JsonElement): OddsMarket? {
            val outs = bo["outcomes"].arr().filter { it["status"].str().let { s -> s == null || s == "OPEN" } }
            if (outs.isEmpty()) return null
            val types = outs.mapNotNull { it["type"].str() }
            fun odds(o: JsonElement) = o["odds"].dbl()?.div(1000.0)
            return when {
                "OT_CROSS" in types && "OT_ONE" in types -> OddsMarket("Unibet", "Match Winner", outs.mapNotNull { o ->
                    val label = when (o["type"].str()) { "OT_ONE" -> "Home"; "OT_CROSS" -> "Draw"; "OT_TWO" -> "Away"; else -> null }
                    val v = odds(o); if (label == null || v == null) null else OddsOutcome(label, v)
                })
                "OT_ONE" in types && "OT_TWO" in types -> OddsMarket("Unibet", "Moneyline (inkl. övertid)", outs.mapNotNull { o ->
                    val label = when (o["type"].str()) { "OT_ONE" -> "Home"; "OT_TWO" -> "Away"; else -> null }
                    val v = odds(o); if (label == null || v == null) null else OddsOutcome(label, v)
                })
                "OT_OVER" in types && "OT_UNDER" in types -> {
                    val line = outs.firstNotNullOfOrNull { it["line"].dbl() }?.div(1000.0) ?: return null
                    val l = if (line % 1.0 == 0.0) line.toInt().toString() else line.toString()
                    OddsMarket("Unibet", "Total Goals", outs.mapNotNull { o ->
                        val label = when (o["type"].str()) { "OT_OVER" -> "Over $l"; "OT_UNDER" -> "Under $l"; else -> null }
                        val v = odds(o); if (label == null || v == null) null else OddsOutcome(label, v)
                    })
                }
                else -> null
            }?.takeIf { it.outcomes.size >= 2 }
        }

        fun isHockeyAllsvenskan(e: KambiEvent) =
            e.pathKeys.any { "allsvenskan" in it } || e.group.contains("allsvenskan", ignoreCase = true)
        fun isShl(e: KambiEvent) = e.pathKeys.any { it == "shl" } || e.group.equals("SHL", true)
        fun isNhl(e: KambiEvent) = e.pathKeys.any { it == "nhl" } || e.group.equals("NHL", true)
    }
}

/** Lägger på Kambi-odds på NHL- och SHL-matcher från de andra källorna. */
class KambiHockeyOdds(private val kambi: KambiHockey) : MatchEnricher {
    override val name = "kambi-odds"
    override fun enrich(matches: List<Match>, date: LocalDate): Pair<List<Match>, String?> {
        val events = kambi.events()
        var hits = 0
        val out = matches.map { m ->
            if (m.sport != Sport.HOCKEY || m.source == "hockeyallsvenskan") return@map m
            val pool = events.filter { if (m.source == "nhl") KambiHockey.isNhl(it) else KambiHockey.isShl(it) }
            val start = runCatching { OffsetDateTime.parse(m.kickoff) }.getOrNull()
            val e = pool.map { it to TeamMatcher.sameTeam(m, it.home, it.away) }
                .filter { (ev, s) -> s >= 0.6 && (start == null || ev.start == null || java.time.Duration.between(start, ev.start).abs().toHours() <= 3) }
                .maxByOrNull { it.second }?.first
            if (e == null || e.markets.isEmpty()) m else { hits++; m.copy(odds = m.odds + e.markets) }
        }
        return out to "$hits matcher fick odds (${events.size} hockeymatcher i flödet)"
    }
}

/**
 * Hockeyallsvenskan: schema och odds från Kambi. Form, tabell och inbördes möten saknas
 * eftersom ligan inte har något öppet statistik-API.
 */
class HockeyAllsvenskanProvider(
    private val kambi: KambiHockey,
    private val zone: ZoneId = ZoneId.of("Europe/Stockholm"),
) : MatchSource {
    override val name = "hockeyallsvenskan"
    override fun fetch(date: LocalDate): SourceResult {
        val before = kambi.calls
        val all = kambi.events()
        val ha = all.filter { KambiHockey.isHockeyAllsvenskan(it) }
        val today = ha.filter { it.start?.atZoneSameInstant(zone)?.toLocalDate() == date }
        val matches = today.map { e ->
            Match(
                id = "hockeyallsvenskan:kambi-${e.id}",
                sport = Sport.HOCKEY, source = "hockeyallsvenskan",
                league = League("hockeyallsvenskan", "HockeyAllsvenskan", "Sverige"),
                kickoff = e.start?.toString() ?: "",
                status = MatchStatus.SCHEDULED,
                home = Team(e.home, e.home), away = Team(e.away, e.away),
                odds = e.markets,
            )
        }
        val warn = if (matches.isEmpty()) listOf("inga matcher idag (${ha.size} kommande i oddsflödet)") else emptyList()
        return SourceResult(name, matches, callsUsed = kambi.calls - before, warnings = warn)
    }
}
