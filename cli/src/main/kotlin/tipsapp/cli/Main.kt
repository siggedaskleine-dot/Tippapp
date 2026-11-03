package tipsapp.cli

import tipsapp.core.DailyFetcher
import tipsapp.core.MatchSource
import tipsapp.core.analysis.Analyzer
import tipsapp.core.football.ApiFootballClient
import tipsapp.core.football.FootballConfig
import tipsapp.core.football.FootballProvider
import tipsapp.core.hockey.NhlProvider
import tipsapp.core.hockey.SwedishHockeyProvider
import tipsapp.core.hockey.SwedishLeagueConfig
import tipsapp.core.http.FileCache
import tipsapp.core.http.JsonHttp
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.Properties
import kotlin.system.exitProcess

/**
 * Kör datagrunden från terminalen:
 *   ./gradlew :cli:run --args="--date 2026-11-03 --out dagens.json"
 *
 * API-nyckeln läses från miljövariabeln APIFOOTBALL_KEY eller filen secrets.properties
 * (apifootball.key=...). Filen ignoreras av git.
 */
fun main(args: Array<String>) {
    val opts = args.toList().windowed(2, 1, partialWindows = true)
        .filter { it[0].startsWith("--") }.associate { it[0].removePrefix("--") to it.getOrNull(1) }

    val date = opts["date"]?.let(LocalDate::parse) ?: LocalDate.now(ZoneId.of("Europe/Stockholm"))
    val out = File(opts["out"] ?: "build/matchday-$date.json")
    val only = opts["sources"]?.split(',')?.map { it.trim() }?.toSet()
    val budget = opts["budget"]?.toInt() ?: 2500

    val key = System.getenv("APIFOOTBALL_KEY") ?: readSecret("apifootball.key")
    val http = JsonHttp()
    val cache = FileCache(File(System.getProperty("user.home"), ".tipsapp/cache"))

    val sources = buildList<MatchSource> {
        if (key.isNullOrBlank()) System.err.println("Varning: ingen api-football-nyckel, hoppar över fotboll.")
        else add(FootballProvider(ApiFootballClient(key, http, cache), FootballConfig(callBudget = budget)))
        add(NhlProvider(http, cache))
        add(SwedishHockeyProvider(SwedishLeagueConfig.SHL, http, cache))
    }.filter { only == null || it.name in only }

    if (sources.isEmpty()) { System.err.println("Inga källor valda."); exitProcess(1) }

    val day = DailyFetcher(sources).fetch(date)
    out.parentFile?.mkdirs()
    out.writeText(DailyFetcher.toJson(day))

    println("Datum: ${day.date}  Matcher totalt: ${day.matches.size}")
    day.sources.forEach { s ->
        println(" - ${s.source}: ${if (s.ok) "OK" else "FEL"}, ${s.matches} matcher, ${s.apiCallsUsed} anrop${s.message?.let { " ($it)" } ?: ""}")
    }
    val withOdds = day.matches.count { it.odds.isNotEmpty() }
    val withForm = day.matches.count { it.homeForm != null }
    val withH2h = day.matches.count { it.headToHead.isNotEmpty() }
    println("Med odds: $withOdds  Med form: $withForm  Med inbördes möten: $withH2h")
    println("Sparat till ${out.absolutePath}")

    val analyses = day.matches.mapNotNull { runCatching { Analyzer.analyze(it) }.getOrNull() }
    val byId = day.matches.associateBy { it.id }
    val top = Analyzer.topPicks(analyses, 15)
    println("\nDagens bästa spel (${top.size} av ${analyses.size} analyserade matcher):")
    top.forEachIndexed { i, a ->
        val m = byId.getValue(a.matchId)
        println("${i + 1}. ${m.kickoff.take(16).replace('T', ' ')}  ${m.league.name}: ${m.home.name} – ${m.away.name}")
        println("   ${a.comment}")
    }
    File(out.parentFile, "analys-$date.json").writeText(DailyFetcher.json.encodeToString(kotlinx.serialization.builtins.ListSerializer(tipsapp.core.analysis.MatchAnalysis.serializer()), analyses))
}

private fun readSecret(name: String): String? {
    val f = listOf(File("secrets.properties"), File("../secrets.properties")).firstOrNull { it.exists() } ?: return null
    return Properties().apply { f.inputStream().use { load(it) } }.getProperty(name)
}
