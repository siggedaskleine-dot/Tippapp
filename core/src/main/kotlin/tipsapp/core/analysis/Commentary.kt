package tipsapp.core.analysis

import tipsapp.core.model.*
import java.util.Locale
import kotlin.math.roundToInt

/** Skriver en kort motivering på svenska utifrån datan bakom spelförslaget. */
object Commentary {
    private fun d(x: Double) = String.format(Locale.forLanguageTag("sv-SE"), "%.2f", x)
    private fun d1(x: Double) = String.format(Locale.forLanguageTag("sv-SE"), "%.1f", x)

    private fun crowdKey(p: Pick): String? = if (p.market != "1X2") null else when {
        p.selection.startsWith("1 ") -> "1"; p.selection.startsWith("X") -> "X"; p.selection.startsWith("2 ") -> "2"; else -> null
    }

    fun write(m: Match, pick: Pick, goals: Pair<Double, Double>?, confidence: Int): String {
        val s = mutableListOf<String>()
        val head = buildString {
            append("Spel: ${pick.selection}")
            if (pick.odds != null) append(" @ ${d(pick.odds)}${pick.bookmaker?.let { " ($it)" } ?: ""}")
            append(". Appen bedömer chansen till ${Analyzer.pct(pick.probability)}")
            if (pick.odds != null) {
                val implied = 1 / pick.odds
                append(" mot oddsets ${Analyzer.pct(implied)}")
                pick.expectedValue?.let { ev -> append(if (ev > 0) ", ett värde på +${(ev * 100).roundToInt()} %" else ", alltså inget tydligt spelvärde") }
            } else append(" (odds saknas, så spelvärdet går inte att räkna)")
            append(".")
        }
        s += head

        val hs = m.homeStanding; val aw = m.awayStanding
        if (hs != null && aw != null) s += "${m.home.name} ligger ${hs.rank}:a med ${hs.points} poäng, ${m.away.name} ${aw.rank}:a med ${aw.points} poäng."
        val hf = m.homeForm?.formString?.takeIf { it.isNotBlank() }; val af = m.awayForm?.formString?.takeIf { it.isNotBlank() }
        if (hf != null || af != null) s += "Form: ${m.home.name} ${hf ?: "okänd"}, ${m.away.name} ${af ?: "okänd"}."
        if (m.headToHead.isNotEmpty()) {
            val h2h = m.headToHead.take(5)
            var hw = 0; var dr = 0; var aw2 = 0
            h2h.forEach { g ->
                val hg = g.homeGoals ?: return@forEach; val ag = g.awayGoals ?: return@forEach
                val homeIsHome = g.homeTeam == m.home.name || g.homeTeam == m.home.id || g.homeTeam == m.home.shortName
                val (our, their) = if (homeIsHome) hg to ag else ag to hg
                when { our > their -> hw++; our == their -> dr++; else -> aw2++ }
            }
            s += "Senaste ${h2h.size} mötena: ${m.home.name} ${hw} vinster, ${dr} oavgjorda, ${m.away.name} ${aw2} vinster."
        }
        goals?.let { s += "Förväntade mål: ${d1(it.first)}–${d1(it.second)}." }
        m.extras["apiAdvice"]?.let { s += "api-footballs prognos: $it." }
        for (pb in m.publicBetting.take(2)) {
            s += "${pb.source}: " + pb.shares.entries.joinToString(", ") { "${it.key} ${it.value.roundToInt()} %" } + "."
        }
        crowdKey(pick)?.let { k ->
            m.publicBetting.firstOrNull { it.source.startsWith("Svenska folket") }?.shares?.get(k)?.let { crowd ->
                val diff = pick.probability * 100 - crowd
                if (diff >= 8) s += "Folket underskattar det här utfallet (${crowd.roundToInt()} % mot appens ${Analyzer.pct(pick.probability)})."
                else if (diff <= -15) s += "Obs: folket är mer säkra än appen här (${crowd.roundToInt()} %), så spelet är populärt."
            }
        }
        s += "Säkerhet: $confidence av 5."
        return s.joinToString(" ")
    }
}
