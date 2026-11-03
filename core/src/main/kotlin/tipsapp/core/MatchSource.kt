package tipsapp.core

import tipsapp.core.model.Match
import java.time.LocalDate

/** En datakälla som kan leverera dagens matcher (api-football, NHL, SHL ...). */
interface MatchSource {
    val name: String
    fun fetch(date: LocalDate): SourceResult
}

data class SourceResult(
    val source: String,
    val matches: List<Match>,
    val callsUsed: Int = 0,
    val warnings: List<String> = emptyList(),
    val extra: List<String> = emptyList(),
)
