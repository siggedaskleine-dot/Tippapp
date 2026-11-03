package tipsapp.core.hockey

import kotlinx.serialization.json.JsonElement
import tipsapp.core.MatchSource
import tipsapp.core.SourceResult
import tipsapp.core.http.*
import tipsapp.core.model.*
import java.time.LocalDate

/**
 * NHL via NHL:s öppna webb-API (api-web.nhle.com, ingen nyckel).
 * Datumet tolkas som nordamerikanskt speldatum, dvs. natten mellan [date] och dagen efter i svensk tid.
 *
 * Anrop: /v1/schedule/{datum}, /v1/standings/now, /v1/club-schedule-season/{lag}/now (+ förra säsongen
 * för inbördes möten) och /v1/partner-game/SE/now för odds (bästa försök, kan sakna data).
 */
class NhlProvider(
    private val http: JsonHttp = JsonHttp(),
    private val cache: ResponseCache = MemoryCache(),
    private val baseUrl: String = "https://api-web.nhle.com",
    private val oddsCountry: String = "SE",
) : MatchSource {
    override val name = "nhl"
    private var calls = 0

    private fun get(path: String, ttl: Long): JsonElement {
        val key = "nhl:$path"
        cache.get(key, ttl)?.let { return it }
        return http.get(baseUrl, path).body.also { calls++; cache.put(key, it) }
    }

    override fun fetch(date: LocalDate): SourceResult {
        calls = 0
        val warnings = mutableListOf<String>()
        val schedule = get("v1/schedule/$date", 15 * MIN)
        val games = schedule["gameWeek"].arr()
            .filter { it["date"].str() == date.toString() }
            .flatMap { it["games"].arr() }
            .filter { (it["gameType"].int() ?: 2) in 1..3 }

        val standings = runCatching { parseStandings(get("v1/standings/now", 3 * HOUR)) }
            .onFailure { warnings += "tabell: ${it.message}" }.getOrDefault(emptyList())

        // Odds från NHL:s partners. Saknas svenska odds provas USA (amerikanska odds räknas om).
        var odds = emptyMap<String, List<OddsMarket>>()
        for (country in listOf(oddsCountry, "US").distinct()) {
            odds = runCatching { parseOdds(get("v1/partner-game/$country/now", 30 * MIN)) }
                .onFailure { warnings += "odds $country: ${it.message}" }.getOrDefault(emptyMap())
            if (odds.values.any { it.isNotEmpty() }) break
        }
        if (odds.values.none { it.isNotEmpty() }) warnings += "inga odds från NHL:s partners"

        val teamGames = HashMap<String, List<JsonElement>>()
        fun seasonGames(abbrev: String, season: String?): List<JsonElement> =
            teamGames.getOrPut("$abbrev:$season") {
                val path = if (season == null) "v1/club-schedule-season/$abbrev/now" else "v1/club-schedule-season/$abbrev/$season"
                runCatching { get(path, 6 * HOUR)["games"].arr().toList() }
                    .onFailure { warnings += "schema $abbrev $season: ${it.message}" }.getOrDefault(emptyList())
            }

        val matches = games.map { g ->
            val homeAbbrev = g.path("homeTeam", "abbrev").str() ?: "?"
            val awayAbbrev = g.path("awayTeam", "abbrev").str() ?: "?"
            val season = g["season"].str()
            val prevSeason = season?.takeIf { it.length == 8 }?.let {
                val y = it.take(4).toInt() - 1; "$y${y + 1}"
            }
            val homeSeason = seasonGames(homeAbbrev, null)
            val awaySeason = seasonGames(awayAbbrev, null)
            val homeAll = (homeSeason + (prevSeason?.let { seasonGames(homeAbbrev, it) } ?: emptyList())).distinctBy { it["id"].str() }
            val id = g["id"].str() ?: "?"
            Match(
                id = "nhl:$id",
                sport = Sport.HOCKEY,
                source = "nhl",
                league = League("nhl", "NHL", "USA/Kanada", season),
                kickoff = g["startTimeUTC"].str() ?: "",
                status = mapState(g["gameState"].str(), g["gameScheduleState"].str()),
                home = team(g["homeTeam"]),
                away = team(g["awayTeam"]),
                homeGoals = g.path("homeTeam", "score").int(),
                awayGoals = g.path("awayTeam", "score").int(),
                venue = g.path("venue", "default").str(),
                odds = odds[id] ?: emptyList(),
                homeForm = form(homeAbbrev, homeSeason, id),
                awayForm = form(awayAbbrev, awaySeason, id),
                headToHead = homeAll.filter { isFinished(it) && involves(it, awayAbbrev) && it["id"].str() != id }
                    .map { toPastGame(it) }.sortedByDescending { it.date }.take(10),
                homeStanding = standings.firstOrNull { it.teamId == homeAbbrev },
                awayStanding = standings.firstOrNull { it.teamId == awayAbbrev },
            )
        }
        return SourceResult(name, matches, callsUsed = calls, warnings = warnings)
    }

    companion object {
        private const val MIN = 60_000L
        private const val HOUR = 60 * MIN

        fun mapState(state: String?, scheduleState: String?): MatchStatus = when {
            scheduleState == "PPD" -> MatchStatus.POSTPONED
            scheduleState == "CNCL" -> MatchStatus.CANCELLED
            state == "FUT" || state == "PRE" -> MatchStatus.SCHEDULED
            state == "LIVE" || state == "CRIT" -> MatchStatus.LIVE
            state == "FINAL" || state == "OFF" -> MatchStatus.FINISHED
            else -> MatchStatus.UNKNOWN
        }

        private fun team(t: JsonElement?): Team {
            val place = t.path("placeName", "default").str()
            val common = t.path("commonName", "default").str()
            val abbrev = t["abbrev"].str() ?: "?"
            return Team(abbrev, listOfNotNull(place, common).joinToString(" ").ifBlank { abbrev }, abbrev, t["logo"].str())
        }

        private fun isFinished(g: JsonElement) = g["gameState"].str() in setOf("FINAL", "OFF")
        private fun involves(g: JsonElement, abbrev: String) =
            g.path("homeTeam", "abbrev").str() == abbrev || g.path("awayTeam", "abbrev").str() == abbrev

        private fun toPastGame(g: JsonElement) = PastGame(
            date = g["gameDate"].str() ?: g["startTimeUTC"].str() ?: "",
            homeTeam = g.path("homeTeam", "abbrev").str() ?: "?",
            awayTeam = g.path("awayTeam", "abbrev").str() ?: "?",
            homeGoals = g.path("homeTeam", "score").int(),
            awayGoals = g.path("awayTeam", "score").int(),
            competition = "NHL",
            decidedAfterRegulation = g.path("gameOutcome", "lastPeriodType").str().let { it == "OT" || it == "SO" },
        )

        /** Form: senaste 5 avslutade matcherna, nyast först. W/L, övertidsförlust = O. */
        fun form(abbrev: String, games: List<JsonElement>, excludeId: String): TeamForm? {
            val last = games.filter { isFinished(it) && it["id"].str() != excludeId && (it["gameType"].int() ?: 2) >= 2 }
                .sortedByDescending { it["startTimeUTC"].str() }.take(5)
            if (last.isEmpty()) return null
            val past = last.map { toPastGame(it) }
            val s = past.joinToString("") { p ->
                val isHome = p.homeTeam == abbrev
                val gf = (if (isHome) p.homeGoals else p.awayGoals) ?: 0
                val ga = (if (isHome) p.awayGoals else p.homeGoals) ?: 0
                when { gf > ga -> "W"; p.decidedAfterRegulation -> "O"; else -> "L" }
            }
            return TeamForm(abbrev, s, past)
        }

        fun parseStandings(json: JsonElement): List<StandingRow> = json["standings"].arr().map { s ->
            StandingRow(
                rank = s["leagueSequence"].int() ?: 0,
                teamId = s.path("teamAbbrev", "default").str() ?: "?",
                teamName = s.path("teamName", "default").str() ?: "?",
                played = s["gamesPlayed"].int() ?: 0,
                wins = s["wins"].int() ?: 0,
                losses = s["losses"].int() ?: 0,
                otLosses = s["otLosses"].int() ?: 0,
                goalsFor = s["goalFor"].int() ?: 0,
                goalsAgainst = s["goalAgainst"].int() ?: 0,
                points = s["points"].int() ?: 0,
                form = listOfNotNull(
                    s["l10Wins"].int()?.let { "L10: ${it}-${s["l10Losses"].int()}-${s["l10OtLosses"].int()}" },
                    s["streakCode"].str()?.let { "svit ${it}${s["streakCount"].int() ?: ""}" },
                ).joinToString(", ").ifBlank { null },
                group = s["divisionName"].str(),
            )
        }

        /** NHL:s partner-odds kan vara decimala ("1.85") eller amerikanska ("+150", "-120"). */
        fun toDecimalOdds(v: String): Double? {
            val n = v.trim().toDoubleOrNull() ?: return null
            val american = v.trim().startsWith("+") || v.trim().startsWith("-") || kotlin.math.abs(n) >= 100
            return when {
                !american -> n
                n > 0 -> 1 + n / 100
                n < 0 -> 1 + 100 / -n
                else -> null
            }?.let { Math.round(it * 100) / 100.0 }
        }

        fun parseOdds(json: JsonElement): Map<String, List<OddsMarket>> = json["games"].arr().associate { g ->
            val home = g.path("homeTeam", "odds").arr()
            val away = g.path("awayTeam", "odds").arr()
            val providers = (home + away).mapNotNull { it["providerId"].str() }.distinct()
            (g["gameId"].str() ?: "?") to providers.mapNotNull { p ->
                val h = home.firstOrNull { it["providerId"].str() == p }?.get("value").str()?.let(::toDecimalOdds)
                val a = away.firstOrNull { it["providerId"].str() == p }?.get("value").str()?.let(::toDecimalOdds)
                if (h == null || a == null) null
                else OddsMarket("nhl-partner-$p", "Moneyline (inkl. övertid)", listOf(OddsOutcome("Home", h), OddsOutcome("Away", a)))
            }
        }
    }
}
