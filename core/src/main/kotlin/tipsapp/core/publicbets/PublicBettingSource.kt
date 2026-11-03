package tipsapp.core.publicbets

import tipsapp.core.model.Match
import tipsapp.core.model.PublicBettingShare

/**
 * Steg 3: källor som visar vad andra spelar på (spelfördelning, populäraste spelen,
 * tipssidors tips). Implementeras senare, men datagrunden anropar redan detta gränssnitt
 * så att en ny källa bara behöver läggas till i listan.
 */
interface PublicBettingSource {
    val name: String
    /** Returnerar fördelningar per match-id för de matcher källan känner till. */
    fun fetch(matches: List<Match>): Map<String, List<PublicBettingShare>>
}
