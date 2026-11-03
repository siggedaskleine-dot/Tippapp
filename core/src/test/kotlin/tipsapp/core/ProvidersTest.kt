package tipsapp.core

import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import tipsapp.core.football.ApiFootballClient
import tipsapp.core.football.FootballConfig
import tipsapp.core.football.FootballProvider
import tipsapp.core.hockey.NhlProvider
import tipsapp.core.hockey.SwedishHockeyProvider
import tipsapp.core.hockey.SwedishLeagueConfig
import tipsapp.core.http.JsonHttp
import tipsapp.core.model.MatchStatus
import java.time.LocalDate
import kotlin.test.*

/**
 * Testerna kör mot en lokal låtsasserver med svar i samma format som de riktiga API:erna,
 * så att tolkning, budget och felhantering kan kontrolleras utan nätverk.
 */
class ProvidersTest {
    private val date = LocalDate.parse("2026-11-03")

    private fun server(routes: Map<String, String>, onRequest: (RecordedRequest) -> Unit = {}): MockWebServer =
        MockWebServer().apply {
            dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    onRequest(request)
                    val path = request.requestUrl!!.encodedPath.trimStart('/')
                    val body = routes.entries.firstOrNull { path.startsWith(it.key) }?.value
                        ?: return MockResponse().setResponseCode(404)
                    return MockResponse().setBody(body)
                        .addHeader("x-ratelimit-requests-remaining", "7400")
                        .addHeader("x-ratelimit-requests-limit", "7500")
                }
            }
            start()
        }

    private val fixtures = """
      {"errors":[],"response":[
        {"fixture":{"id":101,"date":"2026-11-03T20:00:00+01:00","venue":{"name":"Strawberry Arena"},"status":{"short":"NS"}},
         "league":{"id":113,"name":"Allsvenskan","country":"Sweden","season":2026,"round":"Regular Season - 30"},
         "teams":{"home":{"id":1,"name":"AIK"},"away":{"id":2,"name":"Hammarby"}},"goals":{"home":null,"away":null}},
        {"fixture":{"id":102,"date":"2026-11-03T13:00:00+01:00","status":{"short":"FT"}},
         "league":{"id":999,"name":"Liten liga","country":"X","season":2026},
         "teams":{"home":{"id":3,"name":"C"},"away":{"id":4,"name":"D"}},"goals":{"home":2,"away":1}}
      ]}"""
    private val odds = """
      {"errors":[],"paging":{"current":1,"total":1},"response":[
        {"fixture":{"id":101},"bookmakers":[
          {"id":8,"name":"Bet365","bets":[
            {"id":1,"name":"Match Winner","values":[{"value":"Home","odd":"2.10"},{"value":"Draw","odd":"3.40"},{"value":"Away","odd":"3.30"}]},
            {"id":99,"name":"Corners","values":[{"value":"Over 9","odd":"1.9"}]}]},
          {"id":77,"name":"Okänd bookie","bets":[{"id":1,"name":"Match Winner","values":[{"value":"Home","odd":"2.0"}]}]}
        ]}]}"""
    private val standings = """
      {"errors":[],"response":[{"league":{"standings":[[
        {"rank":1,"team":{"id":1,"name":"AIK"},"points":60,"form":"WWDWL","group":"Allsvenskan","all":{"played":29,"win":18,"draw":6,"lose":5,"goals":{"for":50,"against":25}}},
        {"rank":4,"team":{"id":2,"name":"Hammarby"},"points":48,"form":"LDWWW","all":{"played":29,"win":14,"draw":6,"lose":9,"goals":{"for":44,"against":33}}}
      ]]}}]}"""
    private val predictions = """
      {"errors":[],"response":[{"predictions":{"advice":"Double chance : AIK or draw","percent":{"home":"45%","draw":"30%","away":"25%"},"under_over":"-3.5"},
        "teams":{"home":{"id":1,"last_5":{"goals":{"for":{"average":"1.8"},"against":{"average":"0.8"}}},"league":{"form":"WWDWLWWDWL"}},
                 "away":{"id":2,"last_5":{"goals":{"for":{"average":"1.4"},"against":{"average":"1.2"}}},"league":{"form":"LDWWW"}}},
        "h2h":[
          {"fixture":{"date":"2025-05-01T19:00:00+02:00"},"league":{"name":"Allsvenskan"},"teams":{"home":{"name":"Hammarby"},"away":{"name":"AIK"}},"goals":{"home":1,"away":1}},
          {"fixture":{"date":"2025-09-10T19:00:00+02:00"},"league":{"name":"Allsvenskan"},"teams":{"home":{"name":"AIK"},"away":{"name":"Hammarby"}},"goals":{"home":2,"away":0}}
        ]}]}"""

    @Test fun football_hamtar_odds_tabell_form_och_inbordes() {
        val s = server(mapOf("fixtures" to fixtures, "odds" to odds, "standings" to standings, "predictions" to predictions))
        val api = ApiFootballClient("test-nyckel", JsonHttp(maxRetries = 0), baseUrl = s.url("/").toString(), minIntervalMillis = 0)
        val res = FootballProvider(api).fetch(date)

        assertEquals(2, res.matches.size)
        val m = res.matches.first { it.id == "apifootball:101" }
        assertEquals(MatchStatus.SCHEDULED, m.status)
        assertEquals("AIK", m.home.name)
        assertEquals(1, m.odds.size, "bara vald bookmaker och marknad sparas")
        assertEquals(2.10, m.odds[0].outcomes.first { it.label == "Home" }.odds)
        assertEquals(1, m.homeStanding?.rank)
        assertEquals("WWDWL", m.homeForm?.formString)
        assertEquals(2, m.headToHead.size)
        assertEquals("2025-09-10T19:00:00+02:00", m.headToHead.first().date, "nyaste mötet först")
        assertEquals("Double chance : AIK or draw", m.extras["apiAdvice"])
        // slutspelad match får inga extra detaljanrop
        assertNull(res.matches.first { it.id == "apifootball:102" }.homeStanding)
        assertEquals(4, res.callsUsed) // fixtures + odds + standings + predictions
        assertTrue(res.extra.any { "7400" in it })
        s.shutdown()
    }

    @Test fun football_respekterar_budget() {
        val s = server(mapOf("fixtures" to fixtures, "odds" to odds, "standings" to standings, "predictions" to predictions))
        val api = ApiFootballClient("k", JsonHttp(maxRetries = 0), baseUrl = s.url("/").toString())
        val res = FootballProvider(api, FootballConfig(callBudget = 2)).fetch(date)
        assertEquals(2, res.callsUsed)
        assertTrue(res.warnings.any { "fick inga detaljer" in it })
        s.shutdown()
    }

    @Test fun football_skickar_nyckel_i_header_och_cachar() {
        val keys = mutableListOf<String?>()
        val s = server(mapOf("fixtures" to fixtures, "odds" to odds, "standings" to standings, "predictions" to predictions)) {
            keys += it.getHeader("x-apisports-key")
        }
        val api = ApiFootballClient("hemlig", JsonHttp(maxRetries = 0), baseUrl = s.url("/").toString())
        val p = FootballProvider(api)
        p.fetch(date); val second = p.fetch(date)
        assertTrue(keys.all { it == "hemlig" })
        assertEquals(0, second.callsUsed, "andra hämtningen tas från cache")
        s.shutdown()
    }

    private val nhlSchedule = """
      {"gameWeek":[{"date":"2026-11-03","games":[
        {"id":2026020150,"season":20262027,"gameType":2,"startTimeUTC":"2026-11-04T00:00:00Z","gameState":"FUT","gameScheduleState":"OK",
         "venue":{"default":"Scotiabank Arena"},
         "homeTeam":{"abbrev":"TOR","placeName":{"default":"Toronto"},"commonName":{"default":"Maple Leafs"}},
         "awayTeam":{"abbrev":"BOS","placeName":{"default":"Boston"},"commonName":{"default":"Bruins"}}}]},
        {"date":"2026-11-04","games":[]}]}"""
    private val nhlStandings = """
      {"standings":[{"leagueSequence":3,"teamAbbrev":{"default":"TOR"},"teamName":{"default":"Toronto Maple Leafs"},"gamesPlayed":12,"wins":8,"losses":3,"otLosses":1,"goalFor":40,"goalAgainst":30,"points":17,"l10Wins":7,"l10Losses":2,"l10OtLosses":1,"streakCode":"W","streakCount":3,"divisionName":"Atlantic"}]}"""
    private fun clubSchedule(team: String) = """
      {"games":[
        {"id":1,"gameType":2,"gameDate":"2026-10-20","startTimeUTC":"2026-10-20T23:00:00Z","gameState":"OFF","homeTeam":{"abbrev":"$team","score":3},"awayTeam":{"abbrev":"BOS","score":2},"gameOutcome":{"lastPeriodType":"OT"}},
        {"id":2,"gameType":2,"gameDate":"2026-10-25","startTimeUTC":"2026-10-25T23:00:00Z","gameState":"OFF","homeTeam":{"abbrev":"NYR","score":4},"awayTeam":{"abbrev":"$team","score":1},"gameOutcome":{"lastPeriodType":"REG"}},
        {"id":2026020150,"gameType":2,"startTimeUTC":"2026-11-04T00:00:00Z","gameState":"FUT","homeTeam":{"abbrev":"TOR"},"awayTeam":{"abbrev":"BOS"}}]}"""
    private val partner = """{"games":[{"gameId":2026020150,"homeTeam":{"abbrev":"TOR","odds":[{"providerId":9,"value":"1.85"}]},"awayTeam":{"abbrev":"BOS","odds":[{"providerId":9,"value":"+150"}]}}]}"""

    @Test fun nhl_tolkar_schema_tabell_form_odds() {
        val s = server(mapOf(
            "v1/schedule/" to nhlSchedule, "v1/standings/" to nhlStandings,
            "v1/club-schedule-season/TOR" to clubSchedule("TOR"), "v1/club-schedule-season/BOS" to clubSchedule("BOS"),
            "v1/partner-game/" to partner,
        ))
        val res = NhlProvider(JsonHttp(maxRetries = 0), baseUrl = s.url("/").toString()).fetch(date)
        val m = res.matches.single()
        assertEquals("Toronto Maple Leafs", m.home.name)
        assertEquals(3, m.homeStanding?.rank)
        assertEquals("LW", m.homeForm?.formString, "nyast först")
        assertEquals(1, m.headToHead.size)
        assertTrue(m.headToHead.single().decidedAfterRegulation)
        assertEquals(1.85, m.odds.single().outcomes[0].odds)
        assertEquals(2.5, m.odds.single().outcomes[1].odds, "+150 räknas om till decimalodds")
        s.shutdown()
    }

    private val ssgt = """{"uuid":"ssgt1","season":{"uuid":"s26","code":"2026"},"series":{"uuid":"qQ9-bb0bzEWUk"},"gameType":{"uuid":"gt1"}}"""
    private fun g(uuid: String, start: String, state: String, h: String, a: String, hs: Int?, as_: Int?, ot: Boolean = false) = """
      {"uuid":"$uuid","startDateTime":"$start","state":"$state","overtime":$ot,"shootout":false,"venueInfo":{"name":"Arena"},
       "homeTeamInfo":{"uuid":"$h","code":"$h","names":{"short":"$h","long":"Lag $h"},"score":${hs ?: "null"}},
       "awayTeamInfo":{"uuid":"$a","code":"$a","names":{"short":"$a","long":"Lag $a"},"score":${as_ ?: "null"}}}"""
    private val shlSchedule = """{"gameInfo":[
        ${g("g1", "2026-10-10T19:00:00+02:00", "post-game", "FBK", "LHC", 2, 3, ot = true)},
        ${g("g2", "2026-10-20T19:00:00+02:00", "post-game", "LHC", "FHC", 4, 1)},
        ${g("g3", "2026-11-03T19:00:00+01:00", "pre-game", "LHC", "FBK", null, null)},
        ${g("g4", "2026-11-04T19:00:00+01:00", "pre-game", "SAIK", "HV71", null, null)}]}"""
    private val shlStandings = """{"leagueStandings":[{"Rank":2,"GP":15,"W":9,"OTW":1,"L":4,"OTL":1,"G":45,"GA":33,"Points":30,"info":{"code":"LHC","teamInfo":{"teamUuid":"LHC","teamNames":{"short":"LHC"}}}}]}"""

    @Test fun shl_tar_dagens_matcher_med_form_och_inbordes() {
        val headers = mutableListOf<String?>()
        val s = server(mapOf(
            "sports-v2/latest-ssgt" to ssgt, "sports-v2/game-schedule" to shlSchedule,
            "statistics-v2/league-standings" to shlStandings,
        )) { headers += it.getHeader("x-s8y-instance-id") }
        val cfg = SwedishLeagueConfig.SHL.copy(baseUrl = s.url("/").toString())
        val res = SwedishHockeyProvider(cfg, JsonHttp(maxRetries = 0)).fetch(date)
        val m = res.matches.single()
        assertEquals("shl:g3", m.id)
        assertEquals("Lag LHC", m.home.name)
        assertEquals("WW", m.homeForm?.formString)
        assertEquals("O", m.awayForm?.formString, "förlust på övertid")
        assertEquals(1, m.headToHead.size)
        assertEquals(2, m.homeStanding?.rank)
        assertTrue(headers.all { it == "shl1_shl" })
        s.shutdown()
    }

    @Test fun en_trasig_kalla_stoppar_inte_de_andra() {
        val broken = object : MatchSource {
            override val name = "trasig"
            override fun fetch(date: LocalDate): SourceResult = error("nere")
        }
        val s = server(mapOf("sports-v2/latest-ssgt" to ssgt, "sports-v2/game-schedule" to shlSchedule, "statistics-v2/league-standings" to shlStandings))
        val shl = SwedishHockeyProvider(SwedishLeagueConfig.SHL.copy(baseUrl = s.url("/").toString()), JsonHttp(maxRetries = 0))
        val day = DailyFetcher(listOf(broken, shl)).fetch(date)
        assertEquals(1, day.matches.size)
        assertFalse(day.sources.first { it.source == "trasig" }.ok)
        assertTrue(DailyFetcher.toJson(day).contains("\"shl:g3\""))
        s.shutdown()
    }
}
