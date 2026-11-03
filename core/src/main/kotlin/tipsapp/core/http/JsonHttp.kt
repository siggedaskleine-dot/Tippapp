package tipsapp.core.http

import kotlinx.serialization.json.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit

class HttpException(val code: Int, message: String) : IOException(message)

data class JsonResponse(val body: JsonElement, val headers: Map<String, String>)

/** Liten JSON-klient över OkHttp. Fungerar likadant på JVM och Android. */
class JsonHttp(
    private val client: OkHttpClient = defaultClient(),
    private val maxRetries: Int = 2,
) {
    val json = Json { ignoreUnknownKeys = true; isLenient = true }

    fun get(
        baseUrl: String,
        path: String,
        query: Map<String, String?> = emptyMap(),
        headers: Map<String, String> = emptyMap(),
    ): JsonResponse {
        val urlBuilder = (baseUrl.trimEnd('/') + "/" + path.trimStart('/')).toHttpUrl().newBuilder()
        query.forEach { (k, v) -> if (v != null) urlBuilder.addQueryParameter(k, v) }
        val request = Request.Builder().url(urlBuilder.build()).apply {
            header("Accept", "application/json")
            header("User-Agent", "tipsapp/0.1")
            headers.forEach { (k, v) -> header(k, v) }
        }.build()

        var lastError: IOException? = null
        repeat(maxRetries + 1) { attempt ->
            try {
                client.newCall(request).execute().use { resp ->
                    val text = resp.body?.string().orEmpty()
                    if (resp.code == 429 || resp.code >= 500) {
                        throw HttpException(resp.code, "HTTP ${resp.code} från ${request.url.host}")
                    }
                    if (!resp.isSuccessful) {
                        // 4xx (utom 429) är inte värt att försöka igen
                        throw NonRetryable(HttpException(resp.code, "HTTP ${resp.code} från ${request.url.host}${request.url.encodedPath}"))
                    }
                    val body = if (text.isBlank()) JsonObject(emptyMap()) else json.parseToJsonElement(text)
                    return JsonResponse(body, resp.headers.toMap().mapKeys { it.key.lowercase() })
                }
            } catch (e: NonRetryable) {
                throw e.inner
            } catch (e: IOException) {
                lastError = e
                if (attempt < maxRetries) Thread.sleep(500L * (attempt + 1))
            }
        }
        throw lastError ?: IOException("Okänt fel")
    }

    private class NonRetryable(val inner: HttpException) : RuntimeException(inner)

    companion object {
        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
    }
}

// Små hjälpare för att läsa JSON utan att krascha på saknade fält.
fun JsonElement?.obj(): JsonObject? = this as? JsonObject
fun JsonElement?.arr(): JsonArray = (this as? JsonArray) ?: JsonArray(emptyList())
fun JsonElement?.str(): String? = (this as? JsonPrimitive)?.takeUnless { it is JsonNull }?.contentOrNull
fun JsonElement?.int(): Int? = (this as? JsonPrimitive)?.let { it.intOrNull ?: it.contentOrNull?.toDoubleOrNull()?.toInt() }
fun JsonElement?.dbl(): Double? = (this as? JsonPrimitive)?.let { it.doubleOrNull ?: it.contentOrNull?.toDoubleOrNull() }
fun JsonElement?.bool(): Boolean? = (this as? JsonPrimitive)?.booleanOrNull
operator fun JsonElement?.get(key: String): JsonElement? = (this as? JsonObject)?.get(key)
/** Läser t.ex. obj.path("teams", "home", "name"). */
fun JsonElement?.path(vararg keys: String): JsonElement? = keys.fold(this) { acc, k -> acc[k] }
