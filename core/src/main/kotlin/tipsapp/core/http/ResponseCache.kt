package tipsapp.core.http

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import java.io.File
import java.security.MessageDigest

/** Cache för API-svar så att samma data inte hämtas (och kostar anrop) två gånger. */
interface ResponseCache {
    fun get(key: String, maxAgeMillis: Long): JsonElement?
    fun put(key: String, value: JsonElement)
}

class MemoryCache(private val clock: () -> Long = System::currentTimeMillis) : ResponseCache {
    private val map = HashMap<String, Pair<Long, JsonElement>>()
    @Synchronized override fun get(key: String, maxAgeMillis: Long) =
        map[key]?.takeIf { clock() - it.first <= maxAgeMillis }?.second
    @Synchronized override fun put(key: String, value: JsonElement) { map[key] = clock() to value }
}

/** Filcache. På Android pekar man den mot context.cacheDir. */
class FileCache(private val dir: File, private val clock: () -> Long = System::currentTimeMillis) : ResponseCache {
    init { dir.mkdirs() }
    private fun fileFor(key: String): File {
        val hash = MessageDigest.getInstance("SHA-1").digest(key.toByteArray()).joinToString("") { "%02x".format(it) }
        return File(dir, "$hash.json")
    }
    override fun get(key: String, maxAgeMillis: Long): JsonElement? {
        val f = fileFor(key)
        if (!f.exists() || clock() - f.lastModified() > maxAgeMillis) return null
        return runCatching { Json.parseToJsonElement(f.readText()) }.getOrNull()
    }
    override fun put(key: String, value: JsonElement) {
        val f = fileFor(key)
        val tmp = File(f.path + ".tmp")
        tmp.writeText(value.toString())
        tmp.renameTo(f)
    }
}
