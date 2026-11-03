package tipsapp.core.ai

import com.anthropic.client.AnthropicClient
import com.anthropic.client.okhttp.AnthropicOkHttpClient
import com.anthropic.core.JsonValue
import com.anthropic.models.beta.AnthropicBeta
import com.anthropic.models.beta.messages.BetaOutputConfig
import com.anthropic.models.beta.messages.BetaStopReason
import com.anthropic.models.beta.messages.MessageCreateParams
import kotlinx.serialization.json.*
import tipsapp.core.analysis.MatchAnalysis
import tipsapp.core.model.Match
import java.time.Duration

/**
 * Skriver motiveringen under en match med Claude. Kräver en egen Anthropic-nyckel.
 * Utan nyckel används den inbyggda mallen i [tipsapp.core.analysis.Commentary].
 */
class AiCommentWriter(apiKey: String, private val model: String = "claude-opus-5-5") {
    private val client: AnthropicClient = AnthropicOkHttpClient.builder()
        .apiKey(apiKey)
        .timeout(Duration.ofSeconds(90))
        .build()

    private val system = """
        Du är en kunnig och ärlig speltipsare för fotboll och ishockey. Du får data om en match och
        appens uträknade spelförslag. Skriv en motivering på svenska, 3–5 meningar, som förklarar
        varför just det spelet rekommenderas: form, tabelläge, inbördes möten, förväntade mål,
        spelvärdet mot oddset och vad andra spelar på om det finns. Nämn en risk. Hitta inte på
        fakta som inte finns i datan (inga skador eller avstängningar om de inte står där).
        Svara bara med motiveringen, utan rubrik.
    """.trimIndent()

    /** Returnerar AI-texten, eller null om modellen avböjde eller svaret var tomt. */
    fun write(match: Match, analysis: MatchAnalysis): String? {
        val params = MessageCreateParams.builder()
            .model(model)
            .maxTokens(2000L)
            .system(system)
            .outputConfig(BetaOutputConfig.builder().effort(BetaOutputConfig.Effort.LOW).build())
            // Om en förfrågan nekas körs den om på en annan modell på serversidan.
            .addBeta(AnthropicBeta.of("server-side-fallback-2026-07-01"))
            .putAdditionalBodyProperty("fallbacks", JsonValue.from("default"))
            .addUserMessage(describe(match, analysis))
            .build()
        val msg = client.beta().messages().create(params)
        if (msg.stopReason().orElse(null) == BetaStopReason.REFUSAL) return null
        return msg.content().mapNotNull { b -> b.text().orElse(null)?.text() }
            .joinToString("\n").trim().ifBlank { null }
    }

    private fun describe(m: Match, a: MatchAnalysis): String {
        val j = buildJsonObject {
            put("liga", "${m.league.country ?: ""} ${m.league.name}".trim())
            put("avspark", m.kickoff)
            put("hemmalag", m.home.name); put("bortalag", m.away.name)
            m.homeStanding?.let { put("hemma_tabell", "plats ${it.rank}, ${it.points} p, ${it.played} matcher, mål ${it.goalsFor}-${it.goalsAgainst}") }
            m.awayStanding?.let { put("borta_tabell", "plats ${it.rank}, ${it.points} p, ${it.played} matcher, mål ${it.goalsFor}-${it.goalsAgainst}") }
            m.homeForm?.let { put("hemma_form", it.formString) }
            m.awayForm?.let { put("borta_form", it.formString) }
            putJsonArray("inbordes") { m.headToHead.take(6).forEach { add("${it.date.take(10)} ${it.homeTeam} ${it.homeGoals}-${it.awayGoals} ${it.awayTeam}") } }
            putJsonObject("spelforslag") {
                put("marknad", a.pick.market); put("val", a.pick.selection)
                put("appens_sannolikhet_procent", Math.round(a.pick.probability * 100))
                a.pick.odds?.let { put("odds", it) }; a.pick.bookmaker?.let { put("bookmaker", it) }
                a.pick.expectedValue?.let { put("spelvarde_procent", Math.round(it * 100)) }
                put("sakerhet_1_till_5", a.confidence)
            }
            putJsonArray("andra_utfall") { a.alternatives.take(4).forEach { add("${it.market}: ${it.selection} ${Math.round(it.probability * 100)} %" + (it.odds?.let { o -> " @ $o" } ?: "")) } }
            putJsonArray("vad_andra_spelar") { m.publicBetting.forEach { p -> add("${p.source}: " + p.shares.entries.joinToString { "${it.key} ${Math.round(it.value)} %" }) } }
            m.extras["apiAdvice"]?.let { put("api_football_prognos", it) }
            put("appens_mallkommentar", a.comment)
        }
        return "Matchdata:\n$j"
    }
}
