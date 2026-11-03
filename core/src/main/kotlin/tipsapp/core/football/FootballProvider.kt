package tipsapp.core.football

import kotlinx.serialization.json.JsonElement
import tipsapp.core.MatchSource
import tipsapp.core.SourceResult
import tipsapp.core.football.ApiFootballClient.Companion.HOUR
import tipsapp.core.football.ApiFootballClient.Companion.MIN
import tipsapp.core.http.*
import tipsapp.core.model.*
import java.time.LocalDate

data class FootballConfig(
    /** Max antal api-football-anrop per hämtning. Pro-planen har 7 500/dygn. */
    val callBudget: Int = 2500,
    /** Tidszon som "dagens matcher" räknas i. */
    val timezone: String = "Europe/Stockholm",
    /** Bookmakers att spara odds från (namn, skiftlägesokänsligt). Tom = alla. */
    val bookmakers: Set<String> = setOf("Bet365", "Unibet", "Pinnacle", "Betfair", "1xBet", "Marathonbet", "William Hill"),
    /** Marknader att spara. Tom = alla. */
    val markets: Set<String> = setOf(
        "Match Winner", "Double Chance", "Goals Over/Under", "Both Teams Score",
        "Asian Handicap", "Home/Away", "First Half Winner",
    ),
    /** Ligor (api-football id) som prioriteras när kvoten inte räcker till alla matcher. */
    val priorityLeagues: List<Int> = listOf(
        113, 114, 39, 140, 135, 78, 61, 2, 3, 848, 40, 88, 94, 144, 103, 119, 179,
    ),
    /** Hämta inte detaljer för matcher som redan är slut. */
    val skipFinished: Boolean = true,
)

/**
 * Hämtar dagens fotboll från api-football: matcher, odds, tabeller, form och inbördes möten.
 *
 * Anropsplan per hämtning:
 *  1 anrop    /fixtures?date=        alla dagens matcher i alla ligor
 *  N anrop    /odds?date=&page=      odds för hela dagen (sidindelat)
 *  1 per liga /standings             tabell + form (cachas 6 h)
 *  1 per match /predictions          form, inbördes möten och api-footballs egen prognos (cachas 6 h)
 * Matcher prioriteras (har odds > prioriterad liga > tidigast) tills budgeten är slut.
 */
class FootballProvider(
    private val api: ApiFootballClient,
    private val config: FootballConfig = FootballConfig(),
) : MatchSource {
    override val name = "api-football"

    override fun fetch(date: LocalDate): SourceResult {
        val startCalls = api.callsMade
        val budgetLeft = { config.callBudget - (api.callsMade - startCalls) }
        val warnings = mutableListOf<String>()

        val fixturesJson = api.get("fixtures", mapOf("date" to date.toString(), "timezone" to config.timezone), 15 * MIN)
        var matches = fixturesJson["response"].arr().mapNotNull { parseFixture(it) }

        // Odds för hela dagen, sida för sida
        val oddsByFixture = HashMap<String, List<OddsMarket>>()
        var page = 1
        var totalPages = 1
        while (page <= totalPages && budgetLeft() > 0) {
            val oddsJson = try {
                api.get("odds", mapOf("date" to date.toString(), "timezone" to config.timezone, "page" to "$page"), 30 * MIN)
            } catch (e: Exception) { warnings += "odds sida $page: ${e.message}"; break }
            totalPages = oddsJson.path("paging", "total").int() ?: 1
            oddsJson["response"].arr().forEach { o ->
                val id = o.path("fixture", "id").str() ?: return@forEach
                oddsByFixture[id] = parseOdds(o)
            }
            page++
        }
        if (page <= totalPages) warnings += "odds: hann bara ${page - 1} av $totalPages sidor inom budgeten"
        matches = matches.map { m -> oddsByFixture[m.rawId()]?.let { m.copy(odds = it) } ?: m }

        // Prioritera vilka matcher som får detaljer
        val prio = config.priorityLeagues.withIndex().associate { it.value.toString() to it.index }
        val candidates = matches
            .filter { !(config.skipFinished && it.status in setOf(MatchStatus.FINISHED, MatchStatus.CANCELLED, MatchStatus.POSTPONED)) }
            .sortedWith(compareBy<Match>({ it.odds.isEmpty() }, { prio[it.league.id.removePrefix("apifootball:")] ?: Int.MAX_VALUE }, { it.kickoff }))

        val standingsCache = HashMap<String, List<StandingRow>?>()
        val enriched = HashMap<String, Match>()
        var skipped = 0
        for (m in candidates) {
            // varje match kan kosta upp till 2 anrop (tabell + prediction)
            if (budgetLeft() < 2) { skipped++; continue }
            var em = m
            val leagueId = m.league.id.removePrefix("apifootball:")
            val season = m.league.season
            if (season != null) {
                val key = "$leagueId:$season"
                val rows = standingsCache.getOrPut(key) {
                    try {
                        parseStandings(api.get("standings", mapOf("league" to leagueId, "season" to season), 6 * HOUR))
                    } catch (e: Exception) { warnings += "tabell $key: ${e.message}"; null }
                }
                if (rows != null) {
                    val h = rows.firstOrNull { it.teamId == m.home.id }
                    val a = rows.firstOrNull { it.teamId == m.away.id }
                    em = em.copy(homeStanding = h, awayStanding = a)
                }
            }
            try {
                val pred = api.get("predictions", mapOf("fixture" to m.rawId()), 6 * HOUR)
                em = applyPrediction(em, pred)
            } catch (e: Exception) { warnings += "prediction ${m.rawId()}: ${e.message}" }
            enriched[m.id] = em
        }
        if (skipped > 0) warnings += "$skipped matcher fick inga detaljer (budget ${config.callBudget} anrop slut)"

        return SourceResult(
            name, matches.map { enriched[it.id] ?: it },
            callsUsed = api.callsMade - startCalls,
            warnings = warnings,
            extra = listOfNotNull(api.remainingToday?.let { "kvar idag: $it av ${api.dailyLimit ?: "?"}" }),
        )
    }

    private fun Match.rawId() = id.removePrefix("apifootball:")

    companion object {
        fun parseFixture(f: JsonElement): Match? {
            val id = f.path("fixture", "id").str() ?: return null
            val league = f["league"]
            return Match(
                id = "apifootball:$id",
                sport = Sport.FOOTBALL,
                source = "api-football",
                league = League(
                    id = "apifootball:${league["id"].str()}",
                    name = league["name"].str() ?: "?",
                    country = league["country"].str(),
                    season = league["season"].str(),
                    logo = league["logo"].str(),
                ),
                kickoff = f.path("fixture", "date").str() ?: "",
                status = mapStatus(f.path("fixture", "status", "short").str()),
                home = parseTeam(f.path("teams", "home")),
                away = parseTeam(f.path("teams", "away")),
                homeGoals = f.path("goals", "home").int(),
                awayGoals = f.path("goals", "away").int(),
                venue = f.path("fixture", "venue", "name").str(),
                extras = listOfNotNull(f.path("league", "round").str()?.let { "round" to it }).toMap(),
            )
        }

        private fun parseTeam(t: JsonElement?) = Team(
            id = t["id"].str() ?: "?", name = t["name"].str() ?: "?", logo = t["logo"].str(),
        )

        fun mapStatus(short: String?): MatchStatus = when (short) {
            "TBD", "NS" -> MatchStatus.SCHEDULED
            "1H", "HT", "2H", "ET", "BT", "P", "LIVE", "INT", "SUSP" -> MatchStatus.LIVE
            "FT", "AET", "PEN", "AWD", "WO" -> MatchStatus.FINISHED
            "PST" -> MatchStatus.POSTPONED
            "CANC", "ABD" -> MatchStatus.CANCELLED
            else -> MatchStatus.UNKNOWN
        }

        fun parseStandings(json: JsonElement): List<StandingRow> =
            json["response"].arr().flatMap { r ->
                r.path("league", "standings").arr().flatMap { group ->
                    group.arr().map { s ->
                        StandingRow(
                            rank = s["rank"].int() ?: 0,
                            teamId = s.path("team", "id").str() ?: "?",
                            teamName = s.path("team", "name").str() ?: "?",
                            played = s.path("all", "played").int() ?: 0,
                            wins = s.path("all", "win").int() ?: 0,
                            draws = s.path("all", "draw").int() ?: 0,
                            losses = s.path("all", "lose").int() ?: 0,
                            goalsFor = s.path("all", "goals", "for").int() ?: 0,
                            goalsAgainst = s.path("all", "goals", "against").int() ?: 0,
                            points = s["points"].int() ?: 0,
                            form = s["form"].str(),
                            group = s["group"].str(),
                        )
                    }
                }
            }

        private fun FootballProvider.parseOdds(o: JsonElement): List<OddsMarket> =
            o["bookmakers"].arr()
                .filter { b -> config.bookmakers.isEmpty() || config.bookmakers.any { it.equals(b["name"].str(), true) } }
                .flatMap { b ->
                    b["bets"].arr()
                        .filter { bet -> config.markets.isEmpty() || bet["name"].str() in config.markets }
                        .map { bet ->
                            OddsMarket(
                                bookmaker = b["name"].str() ?: "?",
                                market = bet["name"].str() ?: "?",
                                outcomes = bet["values"].arr().mapNotNull { v ->
                                    val odd = v["odd"].dbl() ?: return@mapNotNull null
                                    OddsOutcome(v["value"].str() ?: "?", odd)
                                },
                            )
                        }
                }

        fun applyPrediction(m: Match, json: JsonElement): Match {
            val r = json["response"].arr().firstOrNull() ?: return m
            val h2h = r["h2h"].arr().mapNotNull { f ->
                PastGame(
                    date = f.path("fixture", "date").str() ?: return@mapNotNull null,
                    homeTeam = f.path("teams", "home", "name").str() ?: "?",
                    awayTeam = f.path("teams", "away", "name").str() ?: "?",
                    homeGoals = f.path("goals", "home").int(),
                    awayGoals = f.path("goals", "away").int(),
                    competition = f.path("league", "name").str(),
                )
            }.sortedByDescending { it.date }.take(10)

            fun form(side: String, standing: StandingRow?): TeamForm? {
                val t = r.path("teams", side)
                val f = standing?.form ?: t.path("league", "form").str()?.takeLast(5) ?: return null
                return TeamForm(t["id"].str() ?: "?", f)
            }

            val p = r["predictions"]
            val extras = buildMap {
                putAll(m.extras)
                p.path("advice").str()?.let { put("apiAdvice", it) }
                p.path("percent", "home").str()?.let { put("apiPercentHome", it) }
                p.path("percent", "draw").str()?.let { put("apiPercentDraw", it) }
                p.path("percent", "away").str()?.let { put("apiPercentAway", it) }
                p.path("under_over").str()?.let { put("apiUnderOver", it) }
                r.path("teams", "home", "last_5", "goals", "for", "average").str()?.let { put("homeLast5GoalsForAvg", it) }
                r.path("teams", "home", "last_5", "goals", "against", "average").str()?.let { put("homeLast5GoalsAgainstAvg", it) }
                r.path("teams", "away", "last_5", "goals", "for", "average").str()?.let { put("awayLast5GoalsForAvg", it) }
                r.path("teams", "away", "last_5", "goals", "against", "average").str()?.let { put("awayLast5GoalsAgainstAvg", it) }
            }
            return m.copy(
                headToHead = h2h,
                homeForm = form("home", m.homeStanding) ?: m.homeForm,
                awayForm = form("away", m.awayStanding) ?: m.awayForm,
                extras = extras,
            )
        }
    }
}
