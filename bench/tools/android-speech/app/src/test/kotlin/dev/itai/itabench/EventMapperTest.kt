package dev.itai.itabench

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class EventMapperTest {
    /** `shared/fixtures/native/<name>.events.jsonl`, found by walking up from the working directory. */
    private fun fixture(name: String): List<String> {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val f = File(dir, "shared/fixtures/native/$name.events.jsonl")
            if (f.exists()) return f.readLines().filter { it.isNotBlank() }
            dir = dir.parentFile
        }
        error("fixture $name not found")
    }

    @Test
    fun partialThenFinalForTheSameSegmentMatchesTheFixture() {
        val m = EventMapper("en")
        val lines =
            m.partial("s1", "hel", 400) + m.partial("s1", "hello wor", 700) +
                m.final("s1", "hello world", 1200, 0, 1000) + m.closed(1300)
        assertEquals(fixture("android-partial-then-final"), lines)
    }

    @Test
    fun anEmptyResultGivesNoFinal() {
        assertTrue(EventMapper("en").final("s1", "   ", 5, 0, 1).isEmpty())
    }

    @Test
    fun nothingFollowsAFinalForThatSegment() {
        val m = EventMapper("en")
        assertEquals(1, m.final("s1", "done", 1, 0, 1).size)
        assertTrue(m.final("s1", "again", 2, 0, 1).isEmpty())
        assertTrue(m.partial("s1", "late", 3).isEmpty())
    }

    @Test
    fun networkErrorsBecomeErrorEventsMatchingTheFixture() {
        val m = EventMapper("en")
        assertEquals(fixture("android-error"), m.error(EventMapper.ERROR_NETWORK, 50) + m.closed(60))
    }

    @Test
    fun errorCodesMapToSchemaCodes() {
        val m = EventMapper("he")
        assertTrue(m.error(EventMapper.ERROR_NO_MATCH, 1).isEmpty(), "silence is not an error")
        assertTrue(m.error(EventMapper.ERROR_LANGUAGE_UNAVAILABLE, 1)[0].contains("unsupported_language"))
        assertTrue(m.error(EventMapper.ERROR_INSUFFICIENT_PERMISSIONS, 1)[0].contains("\"auth\""))
        assertTrue(m.error(3, 1)[0].contains("\"internal\""))
    }

    @Test
    fun hebrewTextAndQuotesAreEscapedCorrectly() {
        val line = EventMapper("he").partial("s1", "שלום \"עולם\"", 1)[0]
        assertTrue(line.contains("\"text\":\"שלום \\\"עולם\\\"\""))
    }
}
