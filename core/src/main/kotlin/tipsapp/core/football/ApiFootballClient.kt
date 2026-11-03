package tipsapp.core.football

import kotlinx.serialization.json.JsonElement
import tipsapp.core.http.*

/**
 * Tunn klient mot api-football v3 (https://www.api-football.com/documentation-v3).
 * Varje anrop räknas mot dygnskvoten; svar cachas enligt [ttl].
 */
class ApiFootballClient(
    private val apiKey: String,
    private val http: JsonHttp = JsonHttp(),
    private val cache: ResponseCache = MemoryCache(),
    private val baseUrl: String = "https://v3.football.api-sports.io",
    /** Minsta tid mellan anrop. Pro-planen tillåter 300 anrop/minut. */
    private val minIntervalMillis: Long = 210,
) {
    private var lastCall = 0L
    init { require(apiKey.isNotBlank()) { "api-football-nyckel saknas" } }

    /** Antal riktiga nätverksanrop (cacheträffar räknas inte). */
    var callsMade = 0
        private set
    /** Kvar av dygnskvoten enligt senaste svaret, null om okänt. */
    var remainingToday: Int? = null
        private set
    var dailyLimit: Int? = null
        private set

    fun get(endpoint: String, params: Map<String, String>, ttlMillis: Long): JsonElement {
        val key = "apifootball:$endpoint?" + params.toSortedMap().entries.joinToString("&") { "${it.key}=${it.value}" }
        cache.get(key, ttlMillis)?.let { return it }
        val wait = lastCall + minIntervalMillis - System.currentTimeMillis()
        if (wait > 0) Thread.sleep(wait)
        lastCall = System.currentTimeMillis()
        val resp = http.get(baseUrl, endpoint, params, mapOf("x-apisports-key" to apiKey))
        callsMade++
        resp.headers["x-ratelimit-requests-remaining"]?.toIntOrNull()?.let { remainingToday = it }
        resp.headers["x-ratelimit-requests-limit"]?.toIntOrNull()?.let { dailyLimit = it }
        // api-football svarar 200 även vid fel; felen ligger i "errors"
        val errors = resp.body["errors"]
        val hasErrors = when (errors) {
            is kotlinx.serialization.json.JsonObject -> errors.isNotEmpty()
            is kotlinx.serialization.json.JsonArray -> errors.isNotEmpty()
            else -> false
        }
        if (hasErrors) throw ApiFootballException("api-football fel för $endpoint: $errors")
        cache.put(key, resp.body)
        return resp.body
    }

    /** Hämtar /status (kostar inget enligt api-football) för att läsa kvoten. */
    fun status(): JsonElement = http.get(baseUrl, "status", emptyMap(), mapOf("x-apisports-key" to apiKey)).body

    companion object {
        const val MIN = 60_000L
        const val HOUR = 60 * MIN
    }
}

class ApiFootballException(message: String) : Exception(message)
