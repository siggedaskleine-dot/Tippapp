package tipsapp.core.svenskaspel

import kotlinx.serialization.json.JsonElement
import tipsapp.core.MatchEnricher
import tipsapp.core.http.*
import tipsapp.core.model.Match
import tipsapp.core.model.PublicBettingShare
import tipsapp.core.model.Sport
import tipsapp.core.util.TeamMatcher
import java.time.LocalDate
import java.time.OffsetDateTime

/**
 * "Vad andra spelar på": Svenska folkets streckfördelning (och tio tidningars tips) från
 * Svenska Spels öppna kupong-API för Stryktipset, Europatipset och Topptipset.
 */
class SvenskaSpelFolket(
    private val http: JsonHttp = JsonHttp(),
    private val cache: ResponseCache = MemoryCache(),
    private val baseUrl: String = "https://api.spela.svenskaspel.se",
    private val products: List<String> = listOf("stryktipset", "europatipset", "topptipset"),
) : MatchEnricher {
    override val name = "svenska-folket"

    data class Event(
        val product: String, val home: String, val away: String, val start: OffsetDateTime?,
        val folket: Map<String, Double>?, val tidningar: Map<String, Double>?,
    )

    fun events(): List<Event> = products.flatMap { p ->
        val key = "svs:$p"
        val json = cache.get(key, 30 * 60_000L) ?: runCatching { http.get(baseUrl, "draw/1/$p/draws").body }
            .getOrNull()?.also { cache.put(key, it) } ?: return@flatMap emptyList()
        parse(p, json)
    }

    override fun enrich(matches: List<Match>, date: LocalDate): Pair<List<Match>, String?> {
        val evs = events()
        val football = matches.filter { it.sport == Sport.FOOTBALL }
        val add = HashMap<String, MutableList<PublicBettingShare>>()
        val now = OffsetDateTime.now().toString()
        for (e in evs) {
            val m = TeamMatcher.find(football, e.home, e.away, e.start) ?: continue
            val label = e.product.replaceFirstChar { it.uppercase() }
            e.folket?.let { add.getOrPut(m.id) { mutableListOf() } += PublicBettingShare("Svenska folket ($label)", "1X2", it, now) }
            e.tidningar?.let { add.getOrPut(m.id) { mutableListOf() } += PublicBettingShare("Tio tidningars tips ($label)", "1X2", it, now) }
        }
        val out = matches.map { m -> add[m.id]?.let { m.copy(publicBetting = m.publicBetting + it.distinctBy { s -> s.source }) } ?: m }
        return out to "${add.size} matcher fick folkets fördelning (${evs.size} kupongmatcher)"
    }

    companion object {
        private fun num(e: JsonElement?) = e.str()?.replace(',', '.')?.trim()?.toDoubleOrNull() ?: e.dbl()

        private fun triplet(o: JsonElement?): Map<String, Double>? {
            val one = num(o["one"]); val x = num(o["x"]); val two = num(o["two"])
            if (one == null || x == null || two == null) return null
            val sum = one + x + two
            if (sum <= 0) return null
            // gör om till procent (tidningarnas tips är antal, folket redan procent)
            return mapOf("1" to one / sum * 100, "X" to x / sum * 100, "2" to two / sum * 100)
        }

        fun parse(product: String, json: JsonElement): List<Event> = json["draws"].arr().flatMap { d ->
            d["drawEvents"].arr().mapNotNull { ev ->
                if (ev["cancelled"].bool() == true) return@mapNotNull null
                val match = ev["match"]
                val parts = match["participants"].arr()
                val home = parts.firstOrNull { it["type"].str() == "home" }?.get("name").str()
                val away = parts.firstOrNull { it["type"].str() == "away" }?.get("name").str()
                if (home == null || away == null) {
                    // reserv: "Hemmalag - Bortalag" i beskrivningen
                    val desc = ev["description"].str()?.split(" - ") ?: return@mapNotNull null
                    if (desc.size != 2) return@mapNotNull null
                    return@mapNotNull Event(product, desc[0], desc[1], null, triplet(ev["svenskaFolket"]), triplet(ev["tioTidningarsTips"]))
                }
                Event(
                    product, home, away,
                    match["matchStart"].str()?.let { runCatching { OffsetDateTime.parse(it) }.getOrNull() },
                    triplet(ev["svenskaFolket"]), triplet(ev["tioTidningarsTips"]),
                )
            }
        }
    }
}
