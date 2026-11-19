package dev.itai.itabench

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.widget.TextView
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

/**
 * Benchmark helper (research R-12): takes 16 kHz mono s16le PCM on a TCP socket (reached through
 * `adb forward tcp:7777 tcp:7777`), feeds it to the on-device recognizer, and writes schema events
 * back as JSON lines. Locale comes from the first line the client sends: `locale=he-IL\n`.
 *
 * NOTE: written without the Android SDK on the authoring machine, so it has not been built yet.
 * The mapping logic in [EventMapper] is unit-tested.
 */
class MainActivity : Activity() {
    private val main = Handler(Looper.getMainLooper())
    private val startedAt = System.nanoTime()

    private fun nowMs(): Long = (System.nanoTime() - startedAt) / 1_000_000

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { text = "android-speech: listening on tcp:7777" })
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        }
        thread(name = "server") { serve() }
    }

    private fun serve() {
        ServerSocket(PORT).use { server ->
            while (true) {
                server.accept().use { handle(it) }
            }
        }
    }

    private fun handle(socket: Socket) {
        val input = socket.getInputStream()
        val out = socket.getOutputStream()
        val locale = readLine(input).removePrefix("locale=").ifBlank { "en-US" }
        val mapper = EventMapper(locale.take(2))
        val pipe = ParcelFileDescriptor.createPipe()
        val done = java.util.concurrent.CountDownLatch(1)
        main.post { startRecognizer(locale, pipe[0], mapper, out, done) }
        ParcelFileDescriptor.AutoCloseOutputStream(pipe[1]).use { sink ->
            val buffer = ByteArray(4096)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                sink.write(buffer, 0, n)
            }
        }
        done.await()
    }

    private fun readLine(input: java.io.InputStream): String {
        val sb = StringBuilder()
        while (true) {
            val c = input.read()
            if (c < 0 || c == '\n'.code) break
            sb.append(c.toChar())
        }
        return sb.toString()
    }

    private fun write(
        out: OutputStream,
        lines: List<String>,
    ) {
        synchronized(out) {
            lines.forEach { out.write((it + "\n").toByteArray()) }
            out.flush()
        }
    }

    private fun startRecognizer(
        locale: String,
        audio: ParcelFileDescriptor,
        mapper: EventMapper,
        out: OutputStream,
        done: java.util.concurrent.CountDownLatch,
    ) {
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        var segment = 0

        fun text(bundle: Bundle?): String {
            val results = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            return results?.firstOrNull().orEmpty()
        }

        recognizer.setRecognitionListener(
            object : RecognitionListener {
                override fun onPartialResults(partialResults: Bundle?) =
                    write(out, mapper.partial("s$segment", text(partialResults), nowMs()))

                override fun onResults(results: Bundle?) {
                    write(out, mapper.final("s$segment", text(results), nowMs(), 0, nowMs()))
                    segment++
                    write(out, listOf(mapper.closed(nowMs())))
                    recognizer.destroy()
                    done.countDown()
                }

                override fun onError(error: Int) {
                    write(out, mapper.error(error, nowMs()) + mapper.closed(nowMs()))
                    recognizer.destroy()
                    done.countDown()
                }

                override fun onReadyForSpeech(params: Bundle?) = Unit

                override fun onBeginningOfSpeech() = Unit

                override fun onRmsChanged(rmsdB: Float) = Unit

                override fun onBufferReceived(buffer: ByteArray?) = Unit

                override fun onEndOfSpeech() = Unit

                override fun onEvent(
                    eventType: Int,
                    params: Bundle?,
                ) = Unit
            },
        )
        val intent =
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, audio)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16_000)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, android.media.AudioFormat.ENCODING_PCM_16BIT)
            }
        recognizer.startListening(intent)
    }

    companion object {
        const val PORT = 7777
    }
}
