package tipsapp.core.analysis

import kotlinx.serialization.Serializable
import tipsapp.core.model.*
import kotlin.math.exp
import kotlin.math.roundToInt

/** Ett spelförslag för en match. */
@Serializable
data class Pick(
    /** Marknad på svenska, t.ex. "1X2", "Över/under 2,5 mål". */
    val market: String,
    /** Utfall på svenska, t.ex. "1 (AIK)", "Över 2,5". */
    val selection: String,
    /** Appens bedömda sannolikhet 0–1. */
    val probability: Double,
    /** Bästa hittade odds, null om odds saknas. */
    val odds: Double? = null,
    val bookmaker: String? = null,
    /** Förväntat värde per satsad krona (0.08 = +8 %). Null utan odds. */
    val expectedValue: Double? = null,
)

@Serializable
data class MatchAnalysis(
    val matchId: String,
    /** Huvudförslaget för matchen. */
    val pick: Pick,
    /** Andra utfall som räknats fram, för den som vill se mer. */
    val alternatives: List<Pick>,
    /** 1–5 där 5 är starkast. */
    val confidence: Int,
    /** Motivering på svenska. */
    val comment: String,
    /** Sortering för "dagens bästa spel". Högre är bättre. */
    val score: Double,
)

/**
 * Analysmotor: räknar fram sannolikheter från odds (marknaden), målstatistik (Poisson)
 * och formen, jämför med bästa odds och väljer spelet med bäst värde.
 */
object Analyzer {
    /** Minsta spelvärde för att räknas som "dagens bästa spel" (3 %). */
    const val MIN_EDGE = 0.03

    fun analyze(m: Match): MatchAnalysis? {
        if (m.status == MatchStatus.FINISHED || m.status == MatchStatus.CANCELLED || m.status == MatchStatus.POSTPONED) return null
        val est = estimateGoals(m)
        val poisson = est?.let { scoreMatrix(it.first, it.second) }
        val candidates = if (m.sport == Sport.FOOTBALL) footballCandidates(m, poisson) else hockeyCandidates(m, poisson)
        if (candidates.isEmpty()) return null

        val withValue = candidates.filter { it.expectedValue != null && it.probability >= 0.30 && (it.odds ?: 99.0) <= 6.0 }
        val pick = when {
            withValue.isNotEmpty() -> withValue.maxBy { it.expectedValue!! + it.probability * 0.15 }
            else -> candidates.filter { it.market == candidates.first().market }.maxBy { it.probability }
        }
        val dataPoints = listOf(m.odds.isNotEmpty(), m.homeForm != null, m.homeStanding != null, m.headToHead.isNotEmpty(), est != null).count { it }
        val ev = pick.expectedValue ?: 0.0
        val conf = (1 + dataPoints * 0.2 + ev.coerceAtMost(0.25) * 10 + (pick.probability - 0.45) * 4)
            .roundToInt().coerceIn(1, 5)
        val score = (pick.expectedValue ?: -0.05) * 2 + pick.probability * 0.5 + dataPoints * 0.03
        return MatchAnalysis(m.id, pick, candidates.filter { it != pick }.sortedByDescending { it.probability }.take(5), conf, Commentary.write(m, pick, est, conf), score)
    }

    /** Dagens bästa spel: matcher med odds och positivt värde först. */
    fun topPicks(analyses: List<MatchAnalysis>, n: Int = 10): List<MatchAnalysis> =
        analyses.filter { (it.pick.expectedValue ?: -1.0) >= MIN_EDGE && it.pick.odds != null }
            .sortedByDescending { it.score }.take(n)

    // ---------- sannolikheter ----------

    /** Förväntade mål (hemma, borta) från tabell och senaste matcherna. */
    fun estimateGoals(m: Match): Pair<Double, Double>? {
        val hs = m.homeStanding; val aw = m.awayStanding
        val football = m.sport == Sport.FOOTBALL
        val homeAdv = if (football) 1.12 else 1.05
        var hFor: Double? = null; var hAg: Double? = null; var aFor: Double? = null; var aAg: Double? = null
        if (hs != null && hs.played >= 3 && aw != null && aw.played >= 3) {
            hFor = hs.goalsFor.toDouble() / hs.played; hAg = hs.goalsAgainst.toDouble() / hs.played
            aFor = aw.goalsFor.toDouble() / aw.played; aAg = aw.goalsAgainst.toDouble() / aw.played
        }
        // väg in senaste 5 om api-football gav snitt
        fun ex(k: String) = m.extras[k]?.toDoubleOrNull()
        fun blend(a: Double?, b: Double?) = when { a != null && b != null -> a * 0.6 + b * 0.4; else -> a ?: b }
        hFor = blend(hFor, ex("homeLast5GoalsForAvg")); hAg = blend(hAg, ex("homeLast5GoalsAgainstAvg"))
        aFor = blend(aFor, ex("awayLast5GoalsForAvg")); aAg = blend(aAg, ex("awayLast5GoalsAgainstAvg"))
        // hockey: använd form-matcherna om tabell saknas
        if (hFor == null) m.homeForm?.let { f -> avgGoals(f, m.home.id, m.home.shortName)?.let { hFor = it.first; hAg = it.second } }
        if (aFor == null) m.awayForm?.let { f -> avgGoals(f, m.away.id, m.away.shortName)?.let { aFor = it.first; aAg = it.second } }
        val hf = hFor ?: return null; val ha = hAg ?: return null; val af = aFor ?: return null; val aa = aAg ?: return null
        val lh = ((hf + aa) / 2 * homeAdv).coerceIn(0.2, 6.0)
        val la = ((af + ha) / 2 / homeAdv).coerceIn(0.2, 6.0)
        return lh to la
    }

    private fun avgGoals(f: TeamForm, id: String, short: String?): Pair<Double, Double>? {
        val g = f.lastGames.filter { it.homeGoals != null && it.awayGoals != null }
        if (g.size < 3) return null
        var gf = 0.0; var ga = 0.0
        g.forEach { p ->
            val home = p.homeTeam == id || p.homeTeam == short || p.homeTeam.contains(short ?: "\u0000")
            gf += (if (home) p.homeGoals else p.awayGoals)!!; ga += (if (home) p.awayGoals else p.homeGoals)!!
        }
        return gf / g.size to ga / g.size
    }

    private fun pois(k: Int, l: Double): Double { var r = exp(-l); for (i in 1..k) r *= l / i; return r }

    /** Sannolikhetsmatris för resultat 0–10. */
    fun scoreMatrix(lh: Double, la: Double): Array<DoubleArray> =
        Array(11) { h -> DoubleArray(11) { a -> pois(h, lh) * pois(a, la) } }

    private fun Array<DoubleArray>.sum(f: (Int, Int) -> Boolean): Double {
        var s = 0.0; for (h in indices) for (a in this[h].indices) if (f(h, a)) s += this[h][a]; return s
    }

    /** Marginalfria sannolikheter från alla bookmakers för en marknad (snitt). */
    private fun fairProbs(m: Match, market: String): Map<String, Double>? {
        val books = m.odds.filter { it.market == market && it.outcomes.size >= 2 }
        if (books.isEmpty()) return null
        val acc = HashMap<String, MutableList<Double>>()
        books.forEach { b ->
            val inv = b.outcomes.associate { it.label to 1 / it.odds }
            val total = inv.values.sum()
            inv.forEach { (k, v) -> acc.getOrPut(k) { mutableListOf() } += v / total }
        }
        return acc.mapValues { it.value.average() }
    }

    private fun best(m: Match, market: String, label: String): Pair<Double, String>? =
        m.odds.filter { it.market == market }.mapNotNull { b -> b.outcomes.firstOrNull { it.label == label }?.let { it.odds to b.bookmaker } }
            .maxByOrNull { it.first }

    private fun mix(vararg parts: Pair<Double?, Double>): Double? {
        val present = parts.filter { it.first != null }
        if (present.isEmpty()) return null
        val w = present.sumOf { it.second }
        return present.sumOf { it.first!! * it.second } / w
    }

    private fun pick(m: Match, market: String, label: String, svMarket: String, svSel: String, p: Double): Pick {
        val b = best(m, market, label)
        return Pick(svMarket, svSel, p, b?.first, b?.second, b?.let { p * it.first - 1 })
    }

    private fun footballCandidates(m: Match, mx: Array<DoubleArray>?): List<Pick> {
        val fair = fairProbs(m, "Match Winner")
        fun api(k: String) = m.extras[k]?.removeSuffix("%")?.toDoubleOrNull()?.div(100)
        // Poisson underskattar oavgjort något; justera upp och normalisera
        val pD = mx?.sum { h, a -> h == a }?.times(1.12)
        val rest = pD?.let { 1 - it }
        val rawH = mx?.sum { h, a -> h > a }; val rawA = mx?.sum { h, a -> h < a }
        val pH = if (rawH != null && rawA != null && rest != null) rest * rawH / (rawH + rawA) else null
        val pA = if (rawH != null && rawA != null && rest != null) rest * rawA / (rawH + rawA) else null
        val h = mix(fair?.get("Home") to 0.65, pH to 0.20, api("apiPercentHome") to 0.15)
        val d = mix(fair?.get("Draw") to 0.65, pD to 0.20, api("apiPercentDraw") to 0.15)
        val a = mix(fair?.get("Away") to 0.65, pA to 0.20, api("apiPercentAway") to 0.15)
        val out = mutableListOf<Pick>()
        if (h != null && d != null && a != null) {
            val t = h + d + a
            out += pick(m, "Match Winner", "Home", "1X2", "1 (${m.home.name})", h / t)
            out += pick(m, "Match Winner", "Draw", "1X2", "X (oavgjort)", d / t)
            out += pick(m, "Match Winner", "Away", "1X2", "2 (${m.away.name})", a / t)
        }
        val ouFair = fairProbs(m, "Goals Over/Under")
        val over = mix(ouFair?.get("Over 2.5")?.let { it } to 0.6, mx?.sum { x, y -> x + y >= 3 } to 0.4)
        if (over != null) {
            out += pick(m, "Goals Over/Under", "Over 2.5", "Över/under 2,5 mål", "Över 2,5 mål", over)
            out += pick(m, "Goals Over/Under", "Under 2.5", "Över/under 2,5 mål", "Under 2,5 mål", 1 - over)
        }
        val bttsFair = fairProbs(m, "Both Teams Score")
        val btts = mix(bttsFair?.get("Yes") to 0.6, mx?.sum { x, y -> x > 0 && y > 0 } to 0.4)
        if (btts != null) {
            out += pick(m, "Both Teams Score", "Yes", "Båda lagen gör mål", "Ja", btts)
            out += pick(m, "Both Teams Score", "No", "Båda lagen gör mål", "Nej", 1 - btts)
        }
        return out
    }

    private fun hockeyCandidates(m: Match, mx: Array<DoubleArray>?): List<Pick> {
        val out = mutableListOf<Pick>()
        val pReg = mx?.let { Triple(it.sum { h, a -> h > a }, it.sum { h, a -> h == a }, it.sum { h, a -> h < a }) }

        // 1X2 efter full tid (60 min). Poisson underskattar oavgjort i hockey, så oavgjort-
        // sannolikheten tas från marknaden och modellen får bara fördela resten mellan lagen.
        fairProbs(m, "Match Winner")?.let { fair ->
            val fh = fair["Home"]; val fd = fair["Draw"]; val fa = fair["Away"]
            if (fh != null && fd != null && fa != null) {
                val marketShare = fh / (fh + fa)
                val modelShare = pReg?.let { it.first / (it.first + it.third) }
                val share = mix(marketShare to 0.8, modelShare to 0.2)!!
                out += pick(m, "Match Winner", "Home", "1X2 (full tid)", "1 (${m.home.name})", (1 - fd) * share)
                out += pick(m, "Match Winner", "Draw", "1X2 (full tid)", "X (oavgjort efter 60 min)", fd)
                out += pick(m, "Match Winner", "Away", "1X2 (full tid)", "2 (${m.away.name})", (1 - fd) * (1 - share))
            }
        }

        // Vinnare inklusive övertid; oavgjort efter 60 min avgörs ungefär 52/48 till hemmalaget
        val ml = "Moneyline (inkl. övertid)"
        val fairMl = fairProbs(m, ml)
        val modelHome = pReg?.let { it.first + it.second * 0.52 }
        mix(fairMl?.get("Home") to 0.8, modelHome to 0.2)?.let { h ->
            out += pick(m, ml, "Home", "Vinnare inkl. övertid", "1 (${m.home.name})", h)
            out += pick(m, ml, "Away", "Vinnare inkl. övertid", "2 (${m.away.name})", 1 - h)
        }

        // Över/under: använd bookmakerns linje om den finns, annars 5,5
        val totals = m.odds.filter { it.market == "Total Goals" }
        val lineLabel = totals.flatMap { it.outcomes }.firstOrNull { it.label.startsWith("Over") }?.label?.removePrefix("Over ")
        val line = lineLabel?.toDoubleOrNull() ?: 5.5
        val modelOver = mx?.sum { a, b -> a + b > line }
        val fairOu = fairProbs(m, "Total Goals")
        mix(fairOu?.get("Over ${lineLabel ?: "5.5"}") to 0.6, modelOver to 0.4)?.let { over ->
            val l = lineLabel ?: "5.5"; val sv = l.replace('.', ',')
            out += pick(m, "Total Goals", "Over $l", "Över/under $sv mål", "Över $sv mål", over)
            out += pick(m, "Total Goals", "Under $l", "Över/under $sv mål", "Under $sv mål", 1 - over)
        }
        return out
    }

    internal fun pct(p: Double) = "${(p * 100).roundToInt()} %"
}
