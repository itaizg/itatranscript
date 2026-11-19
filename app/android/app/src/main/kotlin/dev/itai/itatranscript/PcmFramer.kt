package dev.itai.itatranscript

/**
 * Converts float audio at any sample rate to 16 kHz mono s16le, in exact 640-byte (20 ms) frames.
 *
 * Samples that do not fill a frame are carried over to the next call, so nothing is lost between
 * buffers. Pure logic with no Android classes, so it runs in a plain JVM unit test.
 */
class PcmFramer {
    private var input = ArrayList<Float>()
    private var position = 0.0
    private var rate = 0.0
    private val carry = ArrayList<Short>()

    /** Adds mono float samples recorded at [sampleRate] and returns every complete frame. */
    fun push(
        samples: FloatArray,
        sampleRate: Double,
    ): List<ByteArray> {
        if (sampleRate != rate) {
            // The rate changed (route change): restart the resampler, keep the carried samples.
            rate = sampleRate
            input = ArrayList()
            position = 0.0
        }
        val ratio = sampleRate / OUTPUT_RATE
        smooth(samples, ratio).forEach { input.add(it) }
        while (position + 1 < input.size) {
            val index = position.toInt()
            val fraction = (position - index).toFloat()
            val value = input[index] * (1 - fraction) + input[index + 1] * fraction
            carry.add((value.coerceIn(-1f, 1f) * 32767).toInt().toShort())
            position += ratio
        }
        val consumed = minOf(position.toInt(), input.size)
        input = ArrayList(input.subList(consumed, input.size))
        position -= consumed

        val frames = ArrayList<ByteArray>()
        while (carry.size >= FRAME_SAMPLES) {
            val bytes = ByteArray(FRAME_BYTES)
            for (i in 0 until FRAME_SAMPLES) {
                val s = carry[i].toInt()
                bytes[2 * i] = (s and 0xFF).toByte()
                bytes[2 * i + 1] = ((s shr 8) and 0xFF).toByte()
            }
            carry.subList(0, FRAME_SAMPLES).clear()
            frames.add(bytes)
        }
        return frames
    }

    /** A 3-tap moving average before decimation, so high frequencies do not fold down. */
    private fun smooth(
        samples: FloatArray,
        ratio: Double,
    ): FloatArray {
        if (ratio < 2 || samples.size <= 2) return samples
        val out = samples.copyOf()
        for (i in 1 until samples.size - 1) {
            out[i] = (samples[i - 1] + samples[i] + samples[i + 1]) / 3
        }
        return out
    }

    companion object {
        const val OUTPUT_RATE = 16_000.0
        const val FRAME_BYTES = 640
        const val FRAME_SAMPLES = 320
    }
}
