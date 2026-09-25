package app.prepsuite.android.feature.voice

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

data class Recording(val file: File, val durationMs: Long, val peak: Float)

// 16 kHz mono PCM written straight to a WAV file: sample-exact offsets for later segment replay,
// and the same buffer drives the live level, so there is only ever one microphone consumer.
class WavRecorder(private val dir: File) {
    @Volatile
    var level = 0f
        private set

    @Volatile
    private var peak = 0f
    private var record: AudioRecord? = null
    private var job: Job? = null
    private var out: RandomAccessFile? = null
    private var file: File? = null
    private var dataBytes = 0L

    @SuppressLint("MissingPermission")
    fun start(scope: CoroutineScope): Boolean {
        if (job != null) return false
        val minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuffer <= 0) return false
        val rec = runCatching {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                max(minBuffer, FRAME * 16),
            )
        }.getOrNull() ?: return false
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            return false
        }
        dir.mkdirs()
        val target = File(dir, "answer-${UUID.randomUUID()}.wav")
        val raf = RandomAccessFile(target, "rw").apply {
            setLength(0)
            write(ByteArray(HEADER_BYTES))
        }
        if (runCatching { rec.startRecording() }.isFailure) {
            rec.release()
            raf.close()
            target.delete()
            return false
        }
        record = rec
        out = raf
        file = target
        dataBytes = 0
        peak = 0f
        level = 0f
        job = scope.launch(Dispatchers.IO) {
            val samples = ShortArray(FRAME)
            val bytes = ByteBuffer.allocate(FRAME * 2).order(ByteOrder.LITTLE_ENDIAN)
            while (isActive) {
                val n = rec.read(samples, 0, FRAME)
                if (n < 0) break
                if (n == 0) continue
                bytes.clear()
                var sum = 0.0
                for (i in 0 until n) {
                    val s = samples[i]
                    bytes.putShort(s)
                    val v = s.toDouble()
                    sum += v * v
                }
                raf.write(bytes.array(), 0, n * 2)
                dataBytes += n * 2
                val rms = sqrt(sum / n) / 32768.0
                val db = 20 * log10(max(rms, 1e-6))
                val l = ((db + 55.0) / 43.0).coerceIn(0.0, 1.0).toFloat()
                level = l
                if (l > peak) peak = l
            }
        }
        return true
    }

    suspend fun stop(): Recording? {
        val running = job ?: return null
        running.cancel()
        running.join()
        job = null
        val rec = record
        val raf = out
        val target = file
        record = null
        out = null
        file = null
        runCatching { rec?.stop() }
        rec?.release()
        level = 0f
        if (raf == null || target == null) return null
        return runCatching {
            raf.seek(0)
            raf.write(wavHeader(dataBytes.toInt()))
            raf.fd.sync()
            raf.close()
            Recording(target, dataBytes * 1000 / (SAMPLE_RATE * 2), peak)
        }.getOrElse {
            runCatching { raf.close() }
            null
        }
    }

    companion object {
        const val SAMPLE_RATE = 16_000
        private const val FRAME = 320
        private const val HEADER_BYTES = 44

        private fun wavHeader(dataBytes: Int): ByteArray = ByteBuffer.allocate(HEADER_BYTES).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(Charsets.US_ASCII))
            putInt(36 + dataBytes)
            put("WAVE".toByteArray(Charsets.US_ASCII))
            put("fmt ".toByteArray(Charsets.US_ASCII))
            putInt(16)
            putShort(1.toShort())
            putShort(1.toShort())
            putInt(SAMPLE_RATE)
            putInt(SAMPLE_RATE * 2)
            putShort(2.toShort())
            putShort(16.toShort())
            put("data".toByteArray(Charsets.US_ASCII))
            putInt(dataBytes)
        }.array()
    }
}

// Wraps the installed TextToSpeech engine. speak() suspends until the utterance ends, so the
// microphone can never open while the question is still being spoken.
class QuestionSpeaker(context: Context) {
    private val ready = CompletableDeferred<Boolean>()
    private val pending = ConcurrentHashMap<String, CompletableDeferred<Unit>>()
    private var tts: TextToSpeech? = null

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            val engine = tts
            val ok = status == TextToSpeech.SUCCESS && engine != null &&
                engine.setLanguage(Locale.US).let { it != TextToSpeech.LANG_MISSING_DATA && it != TextToSpeech.LANG_NOT_SUPPORTED }
            if (ok && engine != null) {
                engine.setSpeechRate(0.95f)
                engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String) = Unit
                    override fun onDone(utteranceId: String) = finish(utteranceId)

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String) = finish(utteranceId)
                    override fun onError(utteranceId: String, errorCode: Int) = finish(utteranceId)
                    override fun onStop(utteranceId: String, interrupted: Boolean) = finish(utteranceId)
                })
            }
            ready.complete(ok)
        }
    }

    private fun finish(id: String) {
        pending.remove(id)?.complete(Unit)
    }

    suspend fun speak(text: String): Boolean {
        val ok = withTimeoutOrNull(2_500) { ready.await() } ?: false
        val engine = tts
        if (!ok || engine == null) return false
        val id = UUID.randomUUID().toString()
        val done = CompletableDeferred<Unit>()
        pending[id] = done
        if (engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id) != TextToSpeech.SUCCESS) {
            pending.remove(id)
            return false
        }
        withTimeoutOrNull(30_000) { done.await() }
        return true
    }

    fun stop() {
        tts?.stop()
        pending.values.forEach { it.complete(Unit) }
        pending.clear()
    }

    fun release() {
        stop()
        tts?.shutdown()
        tts = null
    }
}
