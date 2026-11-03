package tipsapp.core.model

import kotlinx.serialization.Serializable

/**
 * Gemensam datamodell för fotboll och hockey. Allt som analysmotorn (steg 2)
 * och Android-appen (steg 4) behöver om en match samlas i [Match].
 */
@Serializable
enum class Sport { FOOTBALL, HOCKEY }

@Serializable
enum class MatchStatus { SCHEDULED, LIVE, FINISHED, POSTPONED, CANCELLED, UNKNOWN }

@Serializable
data class League(
    val id: String,
    val name: String,
    val country: String? = null,
    val season: String? = null,
    val logo: String? = null,
)

@Serializable
data class Team(
    val id: String,
    val name: String,
    val shortName: String? = null,
    val logo: String? = null,
)

/** Ett resultat i ett tidigare möte, används för både form och inbördes möten. */
@Serializable
data class PastGame(
    val date: String,
    val homeTeam: String,
    val awayTeam: String,
    val homeGoals: Int?,
    val awayGoals: Int?,
    val competition: String? = null,
    /** Matchen avgjordes på övertid eller straffar (hockey). */
    val decidedAfterRegulation: Boolean = false,
)

/** Senaste matcherna för ett lag, nyast först. formString t.ex. "WWDLW". */
@Serializable
data class TeamForm(
    val teamId: String,
    val formString: String,
    val lastGames: List<PastGame> = emptyList(),
)

@Serializable
data class StandingRow(
    val rank: Int,
    val teamId: String,
    val teamName: String,
    val played: Int,
    val wins: Int,
    val draws: Int = 0,
    val losses: Int,
    val otWins: Int = 0,
    val otLosses: Int = 0,
    val goalsFor: Int,
    val goalsAgainst: Int,
    val points: Int,
    val form: String? = null,
    val group: String? = null,
)

@Serializable
data class OddsOutcome(val label: String, val odds: Double)

/** Ett spelmarknad hos en bookmaker, t.ex. "Match Winner" med 1/X/2. */
@Serializable
data class OddsMarket(
    val bookmaker: String,
    val market: String,
    val outcomes: List<OddsOutcome>,
)

/** Vad andra spelar på, t.ex. Svenska folkets streck eller tidningarnas tips. */
@Serializable
data class PublicBettingShare(
    val source: String,
    val market: String,
    /** Andel per utfall i procent, t.ex. {"1": 52.0, "X": 23.0, "2": 25.0}. */
    val shares: Map<String, Double>,
    val fetchedAt: String,
)

@Serializable
data class Match(
    /** Unikt id med källprefix, t.ex. "apifootball:123456" eller "nhl:2025020123". */
    val id: String,
    val sport: Sport,
    val source: String,
    val league: League,
    /** Starttid i ISO-8601 med tidszon. */
    val kickoff: String,
    val status: MatchStatus,
    val home: Team,
    val away: Team,
    val homeGoals: Int? = null,
    val awayGoals: Int? = null,
    val venue: String? = null,
    val odds: List<OddsMarket> = emptyList(),
    val homeForm: TeamForm? = null,
    val awayForm: TeamForm? = null,
    val headToHead: List<PastGame> = emptyList(),
    val homeStanding: StandingRow? = null,
    val awayStanding: StandingRow? = null,
    val publicBetting: List<PublicBettingShare> = emptyList(),
    /** Extra källspecifik info, t.ex. api-footballs egen prognos. */
    val extras: Map<String, String> = emptyMap(),
)

@Serializable
data class SourceReport(
    val source: String,
    val ok: Boolean,
    val matches: Int,
    val apiCallsUsed: Int = 0,
    val message: String? = null,
)

/** Resultatet av en hämtning: allt som finns för en dag. */
@Serializable
data class MatchDay(
    val date: String,
    val generatedAt: String,
    val matches: List<Match>,
    val sources: List<SourceReport>,
)
