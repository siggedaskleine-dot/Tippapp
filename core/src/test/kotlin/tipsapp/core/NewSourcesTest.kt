package tipsapp.core

import kotlinx.serialization.json.Json
import tipsapp.core.kambi.KambiHockey
import tipsapp.core.svenskaspel.SvenskaSpelFolket
import tipsapp.core.util.TeamMatcher
import tipsapp.core.model.*
import kotlin.test.*

class NewSourcesTest {
    private val kambiJson = """
      {"events":[
        {"event":{"id":1001,"homeName":"Björklöven","awayName":"AIK","start":"2026-11-03T18:00:00Z","group":"HockeyAllsvenskan",
                  "path":[{"termKey":"ice_hockey"},{"termKey":"sweden"},{"termKey":"hockeyallsvenskan"}]},
         "betOffers":[{"criterion":{"label":"Full Tid"},"outcomes":[
           {"type":"OT_ONE","odds":1850,"status":"OPEN"},{"type":"OT_CROSS","odds":4300,"status":"OPEN"},{"type":"OT_TWO","odds":3400,"status":"OPEN"}]}]},
        {"event":{"id":1002,"homeName":"Toronto Maple Leafs","awayName":"Boston Bruins","start":"2026-11-04T00:00:00Z","group":"NHL",
                  "path":[{"termKey":"ice_hockey"},{"termKey":"nhl"}]},
         "betOffers":[{"outcomes":[{"type":"OT_ONE","odds":1900},{"type":"OT_TWO","odds":1950}]},
                      {"outcomes":[{"type":"OT_OVER","odds":1800,"line":6500},{"type":"OT_UNDER","odds":2000,"line":6500}]}]}
      ]}"""

    @Test fun kambi_tolkar_odds_och_ligor() {
        val evs = KambiHockey.parse(Json.parseToJsonElement(kambiJson))
        assertEquals(2, evs.size)
        val ha = evs[0]
        assertTrue(KambiHockey.isHockeyAllsvenskan(ha))
        assertEquals("Match Winner", ha.markets.single().market)
        assertEquals(1.85, ha.markets.single().outcomes.first { it.label == "Home" }.odds)
        val nhl = evs[1]
        assertTrue(KambiHockey.isNhl(nhl))
        assertEquals(listOf("Moneyline (inkl. övertid)", "Total Goals"), nhl.markets.map { it.market })
        assertEquals("Over 6.5", nhl.markets[1].outcomes[0].label)
    }

    private val svsJson = """
      {"draws":[{"drawNumber":4950,"drawEvents":[
        {"eventNumber":1,"cancelled":false,"svenskaFolket":{"one":"52","x":"26","two":"22"},"tioTidningarsTips":{"one":7,"x":2,"two":1},
         "match":{"matchStart":"2026-11-03T20:00:00+01:00","participants":[{"type":"home","name":"Manchester U"},{"type":"away","name":"Liverpool"}]}}]}]}"""

    @Test fun svenska_spel_tolkar_folkets_streck() {
        val evs = SvenskaSpelFolket.parse("stryktipset", Json.parseToJsonElement(svsJson))
        val e = evs.single()
        assertEquals("Manchester U", e.home)
        assertEquals(52.0, e.folket!!["1"])
        assertEquals(70.0, e.tidningar!!["1"])
    }

    @Test fun lagnamn_matchas_mellan_kallor() {
        val m = Match("apifootball:1", Sport.FOOTBALL, "api-football", League("1", "Premier League"),
            "2026-11-03T20:00:00+01:00", MatchStatus.SCHEDULED, Team("33", "Manchester United"), Team("40", "Liverpool"))
        val other = m.copy(id = "apifootball:2", home = Team("50", "Manchester City"), away = Team("40", "Liverpool"))
        val found = TeamMatcher.find(listOf(other, m), "Manchester U", "Liverpool", java.time.OffsetDateTime.parse("2026-11-03T20:00:00+01:00"))
        assertEquals("apifootball:1", found?.id)
        assertTrue(TeamMatcher.similarity("Färjestad BK", "Farjestad") > 0.9)
        assertNull(TeamMatcher.find(listOf(m), "Arsenal", "Chelsea", null))
    }
}
