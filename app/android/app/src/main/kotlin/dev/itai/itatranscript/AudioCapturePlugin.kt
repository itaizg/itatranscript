package dev.itai.itatranscript

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * Streams 16 kHz mono s16le 20 ms frames on `itatranscript/audio`, the same contract as the iOS
 * plugin. Uses VOICE_COMMUNICATION plus the platform noise suppressor, and runs a foreground
 * service so capture survives a locked screen.
 *
 * NOTE: written without the Android SDK on the authoring machine; not yet built or run. The
 * framing it relies on ([PcmFramer]) is unit-tested.
 */
class AudioCapturePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private var context: Context? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var recording = false
    private var worker: Thread? = null
    private var focusListener: AudioManager.OnAudioFocusChangeListener? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        EventChannel(binding.binaryMessenger, "itatranscript/audio").setStreamHandler(this)
        MethodChannel(binding.binaryMessenger, "itatranscript/audio_control").setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
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
            "start" -> {
                runCatching { start() }
                    .onSuccess { result.success(null) }
                    .onFailure { result.error("audio_start", it.message, null) }
            }

            "stop" -> {
                stop()
                result.success(null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun start() {
        val ctx = requireNotNull(context)
        ctx.startForegroundService(Intent(ctx, CaptureService::class.java))
        val minBuffer =
            AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
        val record =
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minBuffer, 8192),
            )
        if (NoiseSuppressor.isAvailable()) NoiseSuppressor.create(record.audioSessionId)
        watchAudioFocus(ctx)
        recording = true
        record.startRecording()
        worker =
            thread(name = "capture") {
                val framer = PcmFramer()
                val buffer = ShortArray(1024)
                var seq = 0
                while (recording) {
                    val n = record.read(buffer, 0, buffer.size)
                    if (n <= 0) continue
                    val floats = FloatArray(n) { buffer[it] / 32768f }
                    for (frame in framer.push(floats, SAMPLE_RATE.toDouble())) {
                        val message = mapOf("seq" to seq, "t_ms" to seq * 20, "pcm" to frame)
                        seq++
                        main.post { sink?.success(message) }
                    }
                }
                record.stop()
                record.release()
            }
    }

    private fun watchAudioFocus(ctx: Context) {
        val manager = ctx.getSystemService(AudioManager::class.java)
        val listener =
            AudioManager.OnAudioFocusChangeListener { change ->
                val paused = change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
                val message =
                    mapOf(
                        "kind" to "interruption",
                        "paused" to paused,
                        "reason" to if (paused) "phone call or another app" else "resumed",
                    )
                main.post { sink?.success(message) }
            }
        focusListener = listener
        @Suppress("DEPRECATION")
        manager.requestAudioFocus(listener, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
    }

    private fun stop() {
        recording = false
        worker?.join(500)
        worker = null
        context?.let { ctx ->
            ctx.stopService(Intent(ctx, CaptureService::class.java))
            focusListener?.let {
                @Suppress("DEPRECATION")
                ctx.getSystemService(AudioManager::class.java).abandonAudioFocus(it)
            }
        }
    }

    companion object {
        private const val SAMPLE_RATE = 16_000
    }
}
