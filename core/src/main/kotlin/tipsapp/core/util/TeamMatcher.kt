package tipsapp.core.util

import tipsapp.core.model.Match
import java.text.Normalizer
import java.time.Duration
import java.time.OffsetDateTime

/** Matchar lagnamn och starttider mellan olika källor (t.ex. "Manchester U" och "Manchester United"). */
object TeamMatcher {
    private val noise = setOf("fc", "if", "bk", "ff", "afc", "sk", "hc", "ik", "the", "cf", "sc", "ac", "fk", "aik.", "club", "de", "hockey", "ifk")

    fun tokens(name: String): List<String> {
        val n = Normalizer.normalize(name.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}"), "")
        return n.split(Regex("[^a-z0-9]+")).filter { it.isNotBlank() && it !in noise }
    }

    /** Likhet 0–1 mellan två lagnamn. */
    fun similarity(a: String, b: String): Double {
        val ta = tokens(a); val tb = tokens(b)
        if (ta.isEmpty() || tb.isEmpty()) return 0.0
        if (ta.joinToString("") == tb.joinToString("")) return 1.0
        var hits = 0
        fun close(x: String, y: String, first: Boolean): Boolean {
            if (x == y) return true
            val (short, long) = if (x.length <= y.length) x to y else y to x
            // förkortningar som "Manchester U" eller "Utd" räknas om de inte är första ordet
            return long.startsWith(short) && (short.length >= 3 || !first)
        }
        for ((i, x) in ta.withIndex()) if (tb.withIndex().any { (j, y) -> close(x, y, i == 0 || j == 0) }) hits++
        return hits.toDouble() / maxOf(ta.size, tb.size).coerceAtLeast(1) * if (ta.first().take(3) == tb.first().take(3)) 1.0 else 0.7
    }

    fun sameTeam(a: Match, homeName: String, awayName: String): Double {
        fun best(t: tipsapp.core.model.Team, other: String) =
            maxOf(similarity(t.name, other), t.shortName?.let { similarity(it, other) } ?: 0.0)
        return (best(a.home, homeName) + best(a.away, awayName)) / 2
    }

    /** Hittar matchen som bäst motsvarar hemma/borta + starttid (inom 3 h). */
    fun find(matches: List<Match>, home: String, away: String, start: OffsetDateTime?, minScore: Double = 0.6): Match? =
        matches.asSequence()
            .filter { m ->
                start == null || runCatching {
                    Duration.between(OffsetDateTime.parse(m.kickoff), start).abs() <= Duration.ofHours(3)
                }.getOrDefault(true)
            }
            .map { it to sameTeam(it, home, away) }
            .filter { it.second >= minScore }
            .maxByOrNull { it.second }?.first
}
