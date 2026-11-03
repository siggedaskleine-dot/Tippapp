package tipsapp.android

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import tipsapp.core.DailyFetcher
import tipsapp.core.MatchSource
import tipsapp.core.analysis.Analyzer
import tipsapp.core.analysis.MatchAnalysis
import tipsapp.core.football.ApiFootballClient
import tipsapp.core.football.FootballConfig
import tipsapp.core.football.FootballProvider
import tipsapp.core.hockey.NhlProvider
import tipsapp.core.hockey.SwedishHockeyProvider
import tipsapp.core.hockey.SwedishLeagueConfig
import tipsapp.core.http.FileCache
import tipsapp.core.http.JsonHttp
import tipsapp.core.ai.AiCommentWriter
import tipsapp.core.kambi.HockeyAllsvenskanProvider
import tipsapp.core.kambi.KambiHockey
import tipsapp.core.kambi.KambiHockeyOdds
import tipsapp.core.svenskaspel.SvenskaSpelFolket
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import tipsapp.core.model.Match
import tipsapp.core.model.MatchDay
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

data class AnalyzedMatch(val match: Match, val analysis: MatchAnalysis?)

/** Hämtar, analyserar och sparar dagens matcher på telefonen. */
class Repository(private val context: Context) {
    private val prefs by lazy {
        val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(
            context, "tipsapp_secrets", key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    var apiKey: String
        get() = prefs.getString("apifootball_key", "") ?: ""
        set(v) = prefs.edit().putString("apifootball_key", v.trim()).apply()

    var anthropicKey: String
        get() = prefs.getString("anthropic_key", "") ?: ""
        set(v) = prefs.edit().putString("anthropic_key", v.trim()).apply()

    var callBudget: Int
        get() = prefs.getInt("budget", 300)
        set(v) = prefs.edit().putInt("budget", v).apply()

    private val http = JsonHttp()
    private val cache = FileCache(File(context.cacheDir, "api"))
    private val kambi = KambiHockey(http, cache)

    // ---- AI-kommentarer (sparas per dag) ----
    private val aiSerializer = MapSerializer(String.serializer(), String.serializer())
    private fun aiFile(date: LocalDate) = File(context.filesDir, "ai-$date.json")

    fun loadAiComments(date: LocalDate): Map<String, String> = aiFile(date).takeIf { it.exists() }?.let {
        runCatching { DailyFetcher.json.decodeFromString(aiSerializer, it.readText()) }.getOrNull()
    } ?: emptyMap()

    @Synchronized
    fun saveAiComment(date: LocalDate, matchId: String, text: String) {
        val all = loadAiComments(date) + (matchId to text)
        aiFile(date).writeText(DailyFetcher.json.encodeToString(aiSerializer, all))
    }

    /** Skriver en AI-kommentar. Kastar fel om nyckel saknas eller anropet misslyckas. */
    fun writeAiComment(am: AnalyzedMatch): String {
        val key = anthropicKey.ifBlank { error("Ingen Anthropic-nyckel sparad") }
        val a = am.analysis ?: error("Matchen saknar analys")
        return AiCommentWriter(key).write(am.match, a) ?: error("AI:n gav inget svar")
    }

    private fun dayFile(date: LocalDate) = File(context.filesDir, "matchday-$date.json")

    fun today(): LocalDate = LocalDate.now(ZoneId.of("Europe/Stockholm"))

    fun loadCached(date: LocalDate): MatchDay? = dayFile(date).takeIf { it.exists() }?.let {
        runCatching { DailyFetcher.json.decodeFromString<MatchDay>(it.readText()) }.getOrNull()
    }

    fun refresh(date: LocalDate): MatchDay {
        val key = apiKey
        val sources = buildList<MatchSource> {
            if (key.isNotBlank()) add(FootballProvider(ApiFootballClient(key, http, cache), FootballConfig(callBudget = callBudget)))
            add(NhlProvider(http, cache))
            add(SwedishHockeyProvider(SwedishLeagueConfig.SHL, http, cache))
            add(HockeyAllsvenskanProvider(kambi))
        }
        val enrichers = listOf(KambiHockeyOdds(kambi), SvenskaSpelFolket(http, cache))
        val day = DailyFetcher(sources, enrichers).fetch(date)
        dayFile(date).writeText(DailyFetcher.json.encodeToString(day))
        // städa gamla dagar
        context.filesDir.listFiles { f ->
            (f.name.startsWith("matchday-") || f.name.startsWith("ai-")) && !f.name.contains(date.toString())
        }?.forEach { it.delete() }
        return day
    }

    fun analyze(day: MatchDay): List<AnalyzedMatch> =
        day.matches.map { AnalyzedMatch(it, runCatching { Analyzer.analyze(it) }.getOrNull()) }
}
