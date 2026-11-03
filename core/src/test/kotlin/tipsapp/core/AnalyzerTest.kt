package tipsapp.core

import tipsapp.core.analysis.Analyzer
import tipsapp.core.model.*
import kotlin.test.*

class AnalyzerTest {
    private fun row(id: String, rank: Int, gf: Int, ga: Int) = StandingRow(rank, id, id, 20, 10, 5, 5, goalsFor = gf, goalsAgainst = ga, points = 35)

    private val base = Match(
        id = "apifootball:1", sport = Sport.FOOTBALL, source = "api-football",
        league = League("apifootball:113", "Allsvenskan"), kickoff = "2026-11-03T19:00:00+01:00",
        status = MatchStatus.SCHEDULED, home = Team("1", "AIK"), away = Team("2", "Hammarby"),
        homeStanding = row("1", 1, 45, 15), awayStanding = row("2", 10, 20, 35),
        homeForm = TeamForm("1", "WWWDW"), awayForm = TeamForm("2", "LLDLW"),
    )

    @Test fun hittar_spelvarde_nar_oddset_ar_for_hogt() {
        val m = base.copy(odds = listOf(
            OddsMarket("Bet365", "Match Winner", listOf(OddsOutcome("Home", 1.80), OddsOutcome("Draw", 3.6), OddsOutcome("Away", 4.6))),
            OddsMarket("Unibet", "Match Winner", listOf(OddsOutcome("Home", 2.30), OddsOutcome("Draw", 3.5), OddsOutcome("Away", 4.4))),
        ))
        val a = Analyzer.analyze(m)!!
        assertEquals("1 (AIK)", a.pick.selection)
        assertEquals(2.30, a.pick.odds)
        assertTrue(a.pick.expectedValue!! > 0)
        assertTrue(a.comment.contains("AIK ligger 1:a"))
        assertEquals(listOf(a), Analyzer.topPicks(listOf(a)))
    }

    @Test fun utan_odds_blir_det_mest_sannolika_utfallet() {
        val a = Analyzer.analyze(base)!!
        assertNull(a.pick.odds)
        assertTrue(a.pick.probability > 0.4)
        assertTrue(a.comment.contains("odds saknas"))
        assertTrue(Analyzer.topPicks(listOf(a)).isEmpty())
    }

    @Test fun slutspelade_matcher_analyseras_inte() {
        assertNull(Analyzer.analyze(base.copy(status = MatchStatus.FINISHED)))
    }
}
