package tipsapp.core.hockey

import kotlinx.serialization.json.JsonElement
import tipsapp.core.MatchSource
import tipsapp.core.SourceResult
import tipsapp.core.http.*
import tipsapp.core.model.*
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId

/**
 * Inställningar för en liga på den plattform som shl.se använder (öppet JSON-API under /api,
 * kräver bara headern x-s8y-instance-id).
 */
data class SwedishLeagueConfig(
    val leagueId: String,
    val leagueName: String,
    val baseUrl: String,
    val instanceId: String,
    /** Seriens uuid. Om null letas den upp via /site/settings med [seriesCode]. */
    val seriesUuid: String?,
    val seriesCode: String,
) {
    companion object {
        val SHL = SwedishLeagueConfig(
            leagueId = "shl", leagueName = "SHL",
            baseUrl = "https://www.shl.se/api", instanceId = "shl1_shl",
            seriesUuid = "qQ9-bb0bzEWUk", seriesCode = "SHL",
        )
    }
}

/**
 * SHL (och ev. Hockeyallsvenskan) via shl.se:s publika webb-API.
 *
 * Anrop per hämtning (alla cachas): latest-ssgt (säsong/serie), game-schedule (hela säsongens
 * schema, ger dagens matcher + form + inbördes möten) och league-standings (tabell).
 * Inga odds finns här; de kopplas på från en oddskälla (se README).
 */
class SwedishHockeyProvider(
    private val league: SwedishLeagueConfig,
    private val http: JsonHttp = JsonHttp(),
    private val cache: ResponseCache = MemoryCache(),
    private val zone: ZoneId = ZoneId.of("Europe/Stockholm"),
) : MatchSource {
    override val name = league.leagueId
    private var calls = 0

    private fun get(path: String, query: Map<String, String?> = emptyMap(), ttl: Long): JsonElement {
        val key = "${league.leagueId}:$path?$query"
        cache.get(key, ttl)?.let { return it }
        return http.get(league.baseUrl, path, query, mapOf("x-s8y-instance-id" to league.instanceId)).body
            .also { calls++; cache.put(key, it) }
    }

    private fun seriesUuid(): String = league.seriesUuid ?: run {
        val settings = get("site/settings", ttl = 24 * HOUR)
        settings["teamsInSite"].arr().flatMap { it["series"].arr() }
            .firstOrNull { it["code"].str().equals(league.seriesCode, true) }?.get("uuid").str()
            ?: error("Hittade ingen serie med kod ${league.seriesCode}")
    }

    override fun fetch(date: LocalDate): SourceResult {
        calls = 0
        val warnings = mutableListOf<String>()
        val ssgt = get("sports-v2/latest-ssgt/${seriesUuid()}", ttl = 6 * HOUR)
        val ssgtUuid = ssgt["uuid"].str() ?: error("latest-ssgt saknar uuid")
        val seasonUuid = ssgt.path("season", "uuid").str()
        val seasonCode = ssgt.path("season", "code").str()
        val seriesUuid = ssgt.path("series", "uuid").str() ?: seriesUuid()
        val gameTypeUuid = ssgt.path("gameType", "uuid").str()

        val scheduleJson = get(
            "sports-v2/game-schedule",
            mapOf("seasonUuid" to seasonUuid, "seriesUuid" to seriesUuid, "gameTypeUuid" to gameTypeUuid),
            ttl = 15 * MIN,
        )
        val all = (scheduleJson["gameInfo"] ?: scheduleJson).arr().map { ParsedGame.from(it) }

        val standings = runCatching { parseStandings(get("statistics-v2/league-standings", mapOf("ssgtUuid" to ssgtUuid), ttl = 3 * HOUR)) }
            .onFailure { warnings += "tabell: ${it.message}" }.getOrDefault(emptyList())

        val today = all.filter { g -> g.start?.atZoneSameInstant(zone)?.toLocalDate() == date }
        val finished = all.filter { it.status == MatchStatus.FINISHED }

        val matches = today.map { g ->
            Match(
                id = "${league.leagueId}:${g.uuid}",
                sport = Sport.HOCKEY,
                source = league.leagueId,
                league = League(league.leagueId, league.leagueName, "Sverige", seasonCode),
                kickoff = g.start?.toString() ?: "",
                status = g.status,
                home = g.home, away = g.away,
                homeGoals = g.homeScore, awayGoals = g.awayScore,
                venue = g.venue,
                homeForm = form(g.home.id, finished, g.uuid),
                awayForm = form(g.away.id, finished, g.uuid),
                headToHead = finished.filter { setOf(it.home.id, it.away.id) == setOf(g.home.id, g.away.id) && it.uuid != g.uuid }
                    .sortedByDescending { it.start }.take(10).map { it.toPast(league.leagueName) },
                homeStanding = standings.firstOrNull { it.teamId == g.home.id || it.teamName.equals(g.home.shortName, true) },
                awayStanding = standings.firstOrNull { it.teamId == g.away.id || it.teamName.equals(g.away.shortName, true) },
            )
        }
        if (all.isEmpty()) warnings += "schemat var tomt"
        return SourceResult(name, matches, callsUsed = calls, warnings = warnings)
    }

    internal data class ParsedGame(
        val uuid: String, val start: OffsetDateTime?, val status: MatchStatus,
        val home: Team, val away: Team, val homeScore: Int?, val awayScore: Int?,
        val venue: String?, val afterRegulation: Boolean,
    ) {
        fun toPast(comp: String) = PastGame(
            start?.toLocalDate()?.toString() ?: "", home.name, away.name, homeScore, awayScore, comp, afterRegulation,
        )
        companion object {
            fun from(g: JsonElement): ParsedGame {
                fun team(t: JsonElement?) = Team(
                    id = t["uuid"].str() ?: t["code"].str() ?: "?",
                    name = t.path("names", "long").str() ?: t.path("names", "full").str() ?: t.path("names", "short").str() ?: t["code"].str() ?: "?",
                    shortName = t.path("names", "short").str() ?: t["code"].str(),
                    logo = t["icon"].str() ?: t["logo"].str(),
                )
                val home = g["homeTeamInfo"] ?: g["homeTeam"]
                val away = g["awayTeamInfo"] ?: g["awayTeam"]
                val startStr = g["startDateTime"].str() ?: g["rawStartDateTime"].str() ?: g.path("gameInfo", "startDateTime").str()
                val state = g["state"].str() ?: g.path("gameInfo", "state").str()
                return ParsedGame(
                    uuid = g["uuid"].str() ?: g.path("gameInfo", "gameUuid").str() ?: "?",
                    start = startStr?.let { runCatching { OffsetDateTime.parse(it) }.getOrNull() },
                    status = mapState(state),
                    home = team(home), away = team(away),
                    homeScore = home["score"].int(), awayScore = away["score"].int(),
                    venue = g.path("venueInfo", "name").str() ?: g.path("gameInfo", "arenaName").str(),
                    afterRegulation = g["overtime"].bool() == true || g["shootout"].bool() == true,
                )
            }
        }
    }

    companion object {
        private const val MIN = 60_000L
        private const val HOUR = 60 * MIN

        fun mapState(s: String?): MatchStatus = when (s) {
            "post-game", "post_game", "GameEnded" -> MatchStatus.FINISHED
            "live", "live-game", "Ongoing", "PeriodBreak" -> MatchStatus.LIVE
            "pre-game", "pre_game", "upcoming", "NotStarted" -> MatchStatus.SCHEDULED
            else -> MatchStatus.UNKNOWN
        }

        internal fun form(teamId: String, finished: List<ParsedGame>, excludeUuid: String): TeamForm? {
            val last = finished.filter { (it.home.id == teamId || it.away.id == teamId) && it.uuid != excludeUuid }
                .sortedByDescending { it.start }.take(5)
            if (last.isEmpty()) return null
            val s = last.joinToString("") { g ->
                val home = g.home.id == teamId
                val gf = (if (home) g.homeScore else g.awayScore) ?: 0
                val ga = (if (home) g.awayScore else g.homeScore) ?: 0
                when { gf > ga -> "W"; g.afterRegulation -> "O"; else -> "L" }
            }
            return TeamForm(teamId, s, last.map { it.toPast("") })
        }

        fun parseStandings(json: JsonElement): List<StandingRow> = json["leagueStandings"].arr().map { r ->
            val info = r["info"]
            StandingRow(
                rank = r["Rank"].int() ?: 0,
                teamId = info.path("teamInfo", "teamUuid").str() ?: info["teamUuid"].str() ?: info["code"].str() ?: "?",
                teamName = info.path("teamInfo", "teamNames", "short").str() ?: info.path("teamNames", "short").str()
                    ?: info["siteTeamDisplayName"].str() ?: info["code"].str() ?: "?",
                played = r["GP"].int() ?: 0,
                wins = r["W"].int() ?: 0,
                otWins = r["OTW"].int() ?: 0,
                losses = r["L"].int() ?: 0,
                otLosses = r["OTL"].int() ?: 0,
                goalsFor = r["G"].int() ?: 0,
                goalsAgainst = r["GA"].int() ?: 0,
                points = r["Points"].int() ?: 0,
            )
        }
    }
}
