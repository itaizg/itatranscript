package dev.itai.itabench

/**
 * Maps `SpeechRecognizer` callbacks to `shared/engine-events.schema.json` lines.
 *
 * Plain Kotlin with no Android classes, so it is unit-tested on the JVM. Rules: a partial
 * replaces the earlier one; an empty result produces nothing; exactly one final per segment;
 * nothing follows a final for the same segment.
 */
class EventMapper(
    private val lang: String,
) {
    private val finalised = HashSet<String>()

    /** An in-progress result. */
    fun partial(
        segmentId: String,
        text: String,
        tMs: Long,
        startMs: Long = 0,
    ): List<String> {
        val clean = text.trim()
        if (clean.isEmpty() || segmentId in finalised) return emptyList()
        return listOf(
            """{"type":"partial","t_ms":$tMs,"segment_id":${q(segmentId)},"text":${q(clean)},""" +
                """"lang":${q(lang)},"start_ms":$startMs}""",
        )
    }

    /** A final result; ignored when empty or when the segment already has a final. */
    fun final(
        segmentId: String,
        text: String,
        tMs: Long,
        startMs: Long,
        endMs: Long,
    ): List<String> {
        val clean = text.trim()
        if (clean.isEmpty() || !finalised.add(segmentId)) return emptyList()
        return listOf(
            """{"type":"final","t_ms":$tMs,"segment_id":${q(segmentId)},"text":${q(clean)},""" +
                """"lang":${q(lang)},"start_ms":$startMs,"end_ms":$endMs}""",
        )
    }

    /** A recognizer error code, or nothing for "no match" (silence is not an error). */
    fun error(
        code: Int,
        tMs: Long,
    ): List<String> {
        if (code == ERROR_NO_MATCH) return emptyList()
        val (name, retryable) =
            when (code) {
                ERROR_NETWORK_TIMEOUT, ERROR_NETWORK -> "network" to true
                ERROR_INSUFFICIENT_PERMISSIONS -> "auth" to false
                ERROR_LANGUAGE_NOT_SUPPORTED, ERROR_LANGUAGE_UNAVAILABLE -> "unsupported_language" to false
                else -> "internal" to false
            }
        return listOf(
            """{"type":"error","t_ms":$tMs,"code":"$name","message":"recognizer error $code",""" +
                """"retryable":$retryable}""",
        )
    }

    /** Always the last event. */
    fun closed(tMs: Long): String = """{"type":"closed","t_ms":$tMs}"""

    companion object {
        // Values of android.speech.SpeechRecognizer.ERROR_*, kept here so this class needs no Android.
        const val ERROR_NETWORK_TIMEOUT = 1
        const val ERROR_NETWORK = 2
        const val ERROR_NO_MATCH = 7
        const val ERROR_INSUFFICIENT_PERMISSIONS = 9
        const val ERROR_LANGUAGE_NOT_SUPPORTED = 12
        const val ERROR_LANGUAGE_UNAVAILABLE = 13

        /** A JSON string literal with the required escapes. */
        fun q(value: String): String {
            val out = StringBuilder("\"")
            for (c in value) {
                when {
                    c == '"' -> out.append("\\\"")
                    c == '\\' -> out.append("\\\\")
                    c == '\n' -> out.append("\\n")
                    c == '\r' -> out.append("\\r")
                    c == '\t' -> out.append("\\t")
                    c < ' ' -> out.append("\\u%04x".format(c.code))
                    else -> out.append(c)
                }
            }
            return out.append('"').toString()
        }
    }
}
