package tipsapp.core

import tipsapp.core.model.Match
import java.time.LocalDate

/**
 * Lägger till data på redan hämtade matcher, t.ex. odds från en annan källa eller vad andra
 * spelar på. Returnerar de uppdaterade matcherna och en kort rapport.
 */
interface MatchEnricher {
    val name: String
    fun enrich(matches: List<Match>, date: LocalDate): Pair<List<Match>, String?>
}
