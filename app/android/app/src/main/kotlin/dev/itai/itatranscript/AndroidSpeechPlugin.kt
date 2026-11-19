package dev.itai.itatranscript

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream

/**
 * On-device Android recognition for the Dart `AndroidSpeechAdapter`. Audio is pushed over
 * `itatranscript/android_speech` and fed to the recognizer through a pipe (API 33+); schema events
 * leave on `itatranscript/android_speech_events`.
 *
 * NOTE: written without the Android SDK on the authoring machine; not yet built or run. The
 * callback-to-event mapping ([SpeechEventMapper]) is unit-tested.
 */
class AndroidSpeechPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private var context: Context? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private val startedAt = System.nanoTime()
    private var recognizer: SpeechRecognizer? = null
    private var pipeWriter: OutputStream? = null
    private var mapper = SpeechEventMapper("en")
    private var segment = 0

    private fun nowMs(): Long = (System.nanoTime() - startedAt) / 1_000_000

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        EventChannel(binding.binaryMessenger, "itatranscript/android_speech_events").setStreamHandler(this)
        MethodChannel(binding.binaryMessenger, "itatranscript/android_speech").setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        release()
        context = null
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "open" -> {
                open(call.argument<String>("locale") ?: "en-US")
                result.success(null)
            }

            "push" -> {
                call.argument<ByteArray>("pcm")?.let { pipeWriter?.write(it) }
                result.success(null)
            }

            "finish" -> {
                pipeWriter?.close()
                result.success(null)
            }

            "cancel" -> {
                release()
                emit(listOf(mapper.closed(nowMs())))
                result.success(null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun emit(lines: List<String>) {
        main.post { lines.forEach { sink?.success(org.json.JSONObject(it).toMap()) } }
    }

    private fun org.json.JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { get(it) }

    private fun open(locale: String) {
        val ctx = context ?: return
        mapper = SpeechEventMapper(locale.take(2))
        segment = 0
        val pipe = ParcelFileDescriptor.createPipe()
        pipeWriter = ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(ctx)) {
            emit(mapper.error(SpeechEventMapper.ERROR_LANGUAGE_UNAVAILABLE, nowMs()) + mapper.closed(nowMs()))
            return
        }
        main.post {
            val r = SpeechRecognizer.createOnDeviceSpeechRecognizer(ctx)
            recognizer = r
            r.setRecognitionListener(listener())
            r.startListening(
                Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0])
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16_000)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                },
            )
        }
    }

    private fun text(bundle: Bundle?): String = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()

    private fun listener() =
        object : RecognitionListener {
            override fun onPartialResults(partialResults: Bundle?) = emit(mapper.partial("s$segment", text(partialResults), nowMs()))

            override fun onResults(results: Bundle?) {
                emit(mapper.final("s$segment", text(results), nowMs(), 0, nowMs()))
                segment++
                emit(listOf(mapper.closed(nowMs())))
            }

            override fun onError(error: Int) = emit(mapper.error(error, nowMs()) + mapper.closed(nowMs()))

            override fun onReadyForSpeech(params: Bundle?) = Unit

            override fun onBeginningOfSpeech() = Unit

            override fun onRmsChanged(rmsdB: Float) = Unit

            override fun onBufferReceived(buffer: ByteArray?) = Unit

            override fun onEndOfSpeech() = Unit

            override fun onEvent(
                eventType: Int,
                params: Bundle?,
            ) = Unit
        }

    private fun release() {
        runCatching { pipeWriter?.close() }
        pipeWriter = null
        main.post {
            recognizer?.destroy()
            recognizer = null
        }
    }
}
