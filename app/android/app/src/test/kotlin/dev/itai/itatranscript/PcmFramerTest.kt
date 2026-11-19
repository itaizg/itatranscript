package dev.itai.itatranscript

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PcmFramerTest {
    private fun sine(
        frequency: Double,
        rate: Double,
        seconds: Double,
    ): FloatArray = FloatArray((rate * seconds).toInt()) { (sin(2 * PI * frequency * it / rate) * 0.8).toFloat() }

    private fun samples(frames: List<ByteArray>): List<Short> =
        frames.flatMap { frame ->
            (0 until frame.size / 2).map { i ->
                ((frame[2 * i].toInt() and 0xFF) or (frame[2 * i + 1].toInt() shl 8)).toShort()
            }
        }

    @Test
    fun frameSizeIsAlways640() {
        val frames = PcmFramer().push(sine(440.0, 48_000.0, 1.0), 48_000.0)
        assertTrue(frames.isNotEmpty())
        assertTrue(frames.all { it.size == 640 })
    }

    @Test
    fun a48kHzSineKeepsItsFrequencyWithinOnePercent() {
        val out = samples(PcmFramer().push(sine(440.0, 48_000.0, 2.0), 48_000.0))
        var crossings = 0
        for (i in 1 until out.size) if (out[i - 1] < 0 && out[i] >= 0) crossings++
        val measured = crossings / (out.size / 16_000.0)
        assertTrue(abs(measured - 440.0) <= 4.4, "measured $measured Hz")
    }

    @Test
    fun oddBufferSizesLoseNoSamples() {
        val framer = PcmFramer()
        val all = sine(300.0, 48_000.0, 1.5)
        val frames = ArrayList<ByteArray>()
        var index = 0
        for (size in listOf(1, 479, 480, 481, 1_001, 4_097, 333)) {
            if (index >= all.size) break
            val end = minOf(index + size, all.size)
            frames += framer.push(all.copyOfRange(index, end), 48_000.0)
            index = end
        }
        frames += framer.push(all.copyOfRange(index, all.size), 48_000.0)
        assertEquals(all.size / 3.0, samples(frames).size.toDouble(), 324.0)
    }
}
