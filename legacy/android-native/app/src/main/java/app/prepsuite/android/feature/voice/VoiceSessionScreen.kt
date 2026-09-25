package app.prepsuite.android.feature.voice

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaPlayer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.prepsuite.android.PrepSuiteApp
import app.prepsuite.android.R
import app.prepsuite.android.data.Pending
import app.prepsuite.android.data.PracticeMode
import app.prepsuite.android.data.Question
import app.prepsuite.android.data.QuestionBank
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.data.SessionSummary
import app.prepsuite.android.designsystem.IconAction
import app.prepsuite.android.designsystem.Motion
import app.prepsuite.android.designsystem.Notice
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.QuietButton
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.prepApp
import java.util.UUID
import kotlin.math.exp
import kotlin.math.sin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class VoicePhase { Idle, Speaking, YourTurn, Listening, Thinking, Review }

private const val CAP_MS = 120_000L
private const val WORD_MS = 330L

private enum class StopReason { User, Cap, Background }

@Stable
class VoiceSession(
    private val app: PrepSuiteApp,
    private val scope: CoroutineScope,
    val question: Question,
    private val role: RolePack,
    private val isQuiet: () -> Boolean,
) {
    var phase by mutableStateOf(VoicePhase.Idle)
        private set
    var revealStartNanos by mutableLongStateOf(0L)
        private set
    var elapsedMs by mutableLongStateOf(0L)
        private set
    var notice by mutableStateOf<String?>(null)
        private set
    var recording by mutableStateOf<Recording?>(null)
        private set
    var playing by mutableStateOf(false)
        private set
    val waveform = mutableStateListOf<Float>()
    val wordCount = question.text.split(" ").size

    private val recorder = WavRecorder(app.audioDir)
    private val speaker = QuestionSpeaker(app)
    private var introJob: Job? = null
    private var player: MediaPlayer? = null
    private var attempts = 0
    private val historyId = UUID.randomUUID().toString()

    val micLevel: Float get() = recorder.level

    fun begin() {
        introJob?.cancel()
        introJob = scope.launch {
            phase = VoicePhase.Idle
            delay(650)
            phase = VoicePhase.Speaking
            revealStartNanos = System.nanoTime()
            val speech = if (isQuiet()) null else launch { speaker.speak(question.text) }
            delay(wordCount * WORD_MS + 300)
            speech?.join()
            if (phase == VoicePhase.Speaking) phase = VoicePhase.YourTurn
        }
    }

    fun replayQuestion() {
        if (phase == VoicePhase.Listening || phase == VoicePhase.Thinking) return
        speaker.stop()
        begin()
    }

    fun onQuietChanged(quiet: Boolean) {
        if (quiet) speaker.stop()
    }

    fun startRecording() {
        introJob?.cancel()
        speaker.stop()
        stopPlayback()
        notice = null
        if (!recorder.start(app.appScope)) {
            notice = "The microphone couldn't start. Try again, or answer in writing instead."
            return
        }
        attempts++
        waveform.clear()
        elapsedMs = 0
        phase = VoicePhase.Listening
        scope.launch {
            val start = System.nanoTime()
            while (phase == VoicePhase.Listening) {
                elapsedMs = (System.nanoTime() - start) / 1_000_000
                if (waveform.size < elapsedMs / 100) waveform.add(recorder.level)
                if (elapsedMs >= CAP_MS) {
                    finishRecording(StopReason.Cap)
                    break
                }
                delay(50)
            }
        }
    }

    fun stopRecording() = finishRecording(StopReason.User)

    private fun finishRecording(reason: StopReason) {
        if (phase != VoicePhase.Listening) return
        phase = VoicePhase.Thinking
        // Finalising runs in the app scope so the WAV header is written even if this screen closes.
        app.appScope.launch {
            val result = recorder.stop()
            if (reason != StopReason.Background) delay(900)
            val silent = result != null && result.peak < 0.05f
            notice = when {
                result == null -> "The recording couldn't be saved. Please try again."
                reason == StopReason.Background -> "Recording stopped when you left the app. What you said up to then is saved."
                silent -> "We couldn't hear anything. Check the microphone, then record again."
                reason == StopReason.Cap -> "You reached the two-minute limit. Your answer is saved."
                else -> null
            }
            recording = result
            if (result != null) {
                app.history.upsert(
                    SessionSummary(
                        id = historyId,
                        questionText = question.text,
                        role = role,
                        mode = PracticeMode.Voice,
                        attempts = attempts,
                        hasRetry = attempts > 1,
                        completed = !silent,
                        pending = if (silent) Pending.NotFinished else Pending.None,
                        createdAt = System.currentTimeMillis(),
                        durationMs = result.durationMs,
                    ),
                )
            }
            phase = VoicePhase.Review
        }
    }

    fun recordAgain() {
        stopPlayback()
        recording = null
        notice = null
        phase = VoicePhase.YourTurn
    }

    fun togglePlayback() {
        val saved = recording ?: return
        if (playing) {
            stopPlayback()
            return
        }
        player = runCatching {
            MediaPlayer().apply {
                setDataSource(saved.file.absolutePath)
                setOnCompletionListener { stopPlayback() }
                prepare()
                start()
            }
        }.getOrNull()
        playing = player != null
    }

    private fun stopPlayback() {
        player?.let {
            runCatching { it.stop() }
            it.release()
        }
        player = null
        playing = false
    }

    fun onBackgrounded() {
        if (phase == VoicePhase.Listening) finishRecording(StopReason.Background) else {
            speaker.stop()
            stopPlayback()
        }
    }

    fun release() {
        introJob?.cancel()
        speaker.release()
        stopPlayback()
        if (phase == VoicePhase.Listening) app.appScope.launch { recorder.stop() }
    }
}

@Composable
fun VoiceSessionScreen(
    questionIds: List<String>,
    index: Int,
    role: RolePack,
    onClose: () -> Unit,
    onFeedback: () -> Unit,
    onNext: () -> Unit,
    onTypeInstead: () -> Unit,
    onReview: (String?, Long) -> Unit = { _, _ -> onFeedback() },
) {
    val app = prepApp()
    val c = Prep.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val quietState = produceState<Boolean?>(initialValue = null) { app.prefs.quietMode.collect { value = it } }
    val quiet = quietState.value
    val question = remember(questionIds, index) { QuestionBank.byId(questionIds[index]) }
    val session = remember(question) { VoiceSession(app, scope, question, role) { quietState.value == true } }

    DisposableEffect(session) { onDispose { session.release() } }
    LaunchedEffect(session, quiet != null) { if (quiet != null) session.begin() }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, session) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) session.onBackgrounded() }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    var micDenied by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        micDenied = !granted
        if (granted) session.startRecording()
    }
    fun onRecordTap() {
        if (session.phase == VoicePhase.Listening) {
            session.stopRecording()
        } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            micDenied = false
            session.startRecording()
        } else {
            permission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    val reduceMotion = rememberReduceMotion()
    var time by remember { mutableFloatStateOf(0f) }
    var frameNanos by remember { mutableLongStateOf(0L) }
    var level by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(session) {
        var last = 0L
        while (true) {
            withFrameNanos { now ->
                val dt = if (last == 0L) 0f else ((now - last) / 1e9f).coerceIn(0f, 0.05f)
                last = now
                frameNanos = now
                val phaseNow = session.phase
                if (!reduceMotion) time = (time + dt * (if (phaseNow == VoicePhase.Thinking) 0.5f else 1f)) % 3600f
                val target = when (phaseNow) {
                    VoicePhase.Speaking -> if (quietState.value == true) 0.08f else speechEnvelope(time)
                    VoicePhase.Listening -> session.micLevel
                    VoicePhase.Idle, VoicePhase.YourTurn -> 0.05f + 0.05f * sin(time * 1.26f)
                    else -> 0f
                }
                val tau = if (target > level) 0.04f else 0.28f
                level += (target - level) * (1f - exp(-dt / tau))
            }
        }
    }

    val phase = session.phase
    val energy by animateFloatAsState(
        when (phase) {
            VoicePhase.Idle -> 0.15f
            VoicePhase.Speaking -> 0.7f
            VoicePhase.YourTurn -> 0.3f
            VoicePhase.Listening -> 0.55f
            VoicePhase.Thinking -> 0.35f
            VoicePhase.Review -> 0.1f
        },
        tween(700, easing = Motion.decelerate),
        label = "energy",
    )
    val warmth by animateFloatAsState(
        when (phase) {
            VoicePhase.Listening -> 1f
            VoicePhase.YourTurn -> 0.12f
            else -> 0f
        },
        tween(if (phase == VoicePhase.Listening) 600 else 800, easing = Motion.decelerate),
        label = "warmth",
    )
    val orbScale by animateFloatAsState(if (phase == VoicePhase.Review) 0.55f else 1f, tween(700, easing = Motion.decelerate), label = "orbScale")
    val orbAlpha by animateFloatAsState(if (phase == VoicePhase.Review) 0.6f else 1f, tween(700), label = "orbAlpha")
    val revealed by remember(session) {
        derivedStateOf {
            when {
                reduceMotion || session.phase.ordinal > VoicePhase.Speaking.ordinal -> session.wordCount.toFloat()
                session.phase == VoicePhase.Idle || session.revealStartNanos == 0L -> 0f
                else -> ((frameNanos - session.revealStartNanos) / 1e6f / WORD_MS).coerceIn(0f, session.wordCount.toFloat())
            }
        }
    }

    Box(Modifier.fillMaxSize().background(c.voiceCanvas)) {
        // Near-black stage with a soft amber light behind the hologram and a darker rim, so the gold reads clearly.
        Canvas(Modifier.fillMaxSize()) {
            val stage = Offset(size.width / 2f, size.height * 0.34f)
            drawRect(
                Brush.radialGradient(
                    colors = listOf(Color(0xFF2A1606).copy(alpha = 0.55f + 0.25f * level), Color(0xFF120A04).copy(alpha = 0.35f), Color.Transparent),
                    center = stage,
                    radius = size.width * 0.75f,
                ),
            )
            drawRect(
                Brush.radialGradient(
                    colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.65f)),
                    center = stage,
                    radius = size.maxDimension * 0.85f,
                ),
            )
        }
        DustField(time = { time }, color = c.voiceWarm.copy(alpha = 0.6f), modifier = Modifier.fillMaxSize())
        BoxWithConstraints(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
        val stageHeight = (maxHeight * 0.43f).coerceIn(140.dp, 360.dp)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            VoiceTopBar(
                index = index,
                total = questionIds.size,
                quiet = quiet == true,
                onQuiet = { q ->
                    scope.launch { app.prefs.setQuietMode(q) }
                    session.onQuietChanged(q)
                },
                onClose = onClose,
            )
            Box(Modifier.fillMaxWidth().height(stageHeight), contentAlignment = Alignment.Center) {
                Box(
                    Modifier
                        .fillMaxHeight(0.96f)
                        .aspectRatio(1f, matchHeightConstraintsFirst = true)
                        .sizeIn(maxWidth = 380.dp, maxHeight = 380.dp)
                        .graphicsLayer {
                            scaleX = orbScale
                            scaleY = orbScale
                            alpha = orbAlpha
                        }
                        .clearAndSetSemantics { },
                ) {
                    PresenceVideo(video = R.raw.presence_loop, level = { level }, modifier = Modifier.fillMaxSize())
                    if (phase == VoicePhase.Listening || phase == VoicePhase.Thinking) TickRing(
                        phase = phase,
                        time = { time },
                        progress = { if (phase == VoicePhase.Listening || phase == VoicePhase.Thinking) session.elapsedMs / CAP_MS.toFloat() else 0f },
                        warmth = { warmth },
                        modifier = Modifier.fillMaxSize().padding(8.dp),
                    )
                }
            }
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = Space.xxl)
                    .animateContentSize(tween(Motion.ENTER, easing = Motion.decelerate)),
            ) {
                val compact = phase.ordinal >= VoicePhase.Listening.ordinal
                RevealedQuestion(
                    text = question.text,
                    revealed = revealed,
                    style = if (compact) Prep.type.questionM else Prep.type.question,
                    color = if (compact) c.text2 else c.text,
                )
                if (phase == VoicePhase.Review) {
                    Spacer(Modifier.height(Space.l))
                    Waveform(levels = session.waveform, color = c.voiceWarm)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        val saved = session.recording
                        Text(
                            if (saved != null) "${formatClock(saved.durationMs)} · Saved on this phone" else "Not saved",
                            style = Prep.type.meta,
                            color = c.text3,
                            modifier = Modifier.weight(1f),
                        )
                        if (saved != null) {
                            QuietButton(
                                text = if (session.playing) "Stop" else "Play",
                                onClick = { session.togglePlayback() },
                                icon = if (session.playing) PrepIcons.Pause else PrepIcons.Play,
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.height(Space.xl))
            BottomCluster(
                session = session,
                quiet = quiet == true,
                micDenied = micDenied,
                isLast = index >= questionIds.lastIndex,
                onRecordTap = { onRecordTap() },
                onFeedback = { onReview(session.recording?.file?.absolutePath, session.recording?.durationMs ?: 0L) },
                onNext = onNext,
                onClose = onClose,
                onTypeInstead = onTypeInstead,
            )
        }
        }
    }
}

@Composable
private fun RevealedQuestion(text: String, revealed: Float, style: TextStyle, color: androidx.compose.ui.graphics.Color) {
    val words = remember(text) { text.split(" ") }
    val annotated = buildAnnotatedString {
        words.forEachIndexed { i, w ->
            withStyle(SpanStyle(color = color.copy(alpha = (revealed - i).coerceIn(0f, 1f)))) { append(w) }
            if (i < words.lastIndex) append(" ")
        }
    }
    Text(annotated, style = style, modifier = Modifier.fillMaxWidth().semantics { contentDescription = text })
}

@Composable
private fun VoiceTopBar(index: Int, total: Int, quiet: Boolean, onQuiet: (Boolean) -> Unit, onClose: () -> Unit) {
    val c = Prep.colors
    Box(Modifier.fillMaxWidth().height(1.dp).background(c.voiceFaint.copy(alpha = 0.45f))) {
        Box(Modifier.fillMaxWidth((index + 1f) / total).fillMaxHeight().background(c.text2))
    }
    Row(
        Modifier.fillMaxWidth().height(56.dp).padding(start = Space.gutter, end = Space.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Question ${index + 1} of $total", style = Prep.type.meta, color = c.text2, modifier = Modifier.weight(1f))
        QuietButton(
            text = if (quiet) "Quiet" else "Read aloud",
            onClick = { onQuiet(!quiet) },
            icon = if (quiet) PrepIcons.SpeakerOff else PrepIcons.Speaker,
        )
        IconAction(PrepIcons.Close, "Close", onClose)
    }
}

@Composable
private fun BottomCluster(
    session: VoiceSession,
    quiet: Boolean,
    micDenied: Boolean,
    isLast: Boolean,
    onRecordTap: () -> Unit,
    onFeedback: () -> Unit,
    onNext: () -> Unit,
    onClose: () -> Unit,
    onTypeInstead: () -> Unit,
) {
    val c = Prep.colors
    val phase = session.phase
    Column(
        Modifier.fillMaxWidth().padding(horizontal = Space.gutter).padding(bottom = Space.s),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val note = session.notice
            ?: if (micDenied) "Microphone access is off. You can answer in writing instead, or allow it in system settings." else null
        if (note != null) {
            Notice(note)
            Spacer(Modifier.height(Space.l))
        }
        if (phase == VoicePhase.Review) {
            PrimaryButton("Review answer", onFeedback, enabled = session.recording != null)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                QuietButton("Record again", { session.recordAgain() }, icon = PrepIcons.Replay)
                if (isLast) QuietButton("Finish", onClose, icon = PrepIcons.Check) else QuietButton("Next question", onNext, icon = PrepIcons.Chevron)
            }
            return@Column
        }
        Text(
            text = when (phase) {
                VoicePhase.Idle -> "Getting ready"
                VoicePhase.Speaking -> if (quiet) "Read the question" else "Listen to the question"
                VoicePhase.YourTurn -> "Your turn — tap Record when you're ready"
                VoicePhase.Listening -> "Recording"
                VoicePhase.Thinking -> "Saving your recording…"
                VoicePhase.Review -> ""
            },
            style = Prep.type.body,
            color = if (phase == VoicePhase.Listening) c.recording else c.text2,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
        Spacer(Modifier.height(Space.s))
        val showTimer = phase == VoicePhase.Listening || phase == VoicePhase.Thinking
        val remaining = CAP_MS - session.elapsedMs
        Text(
            text = if (showTimer && remaining <= 15_000) "${(remaining / 1000).coerceAtLeast(0)} s left" else formatClock(session.elapsedMs),
            style = Prep.type.timer,
            color = if (showTimer && remaining <= 15_000) c.pending else c.text,
            modifier = Modifier.graphicsLayer { alpha = if (showTimer) 1f else 0f },
        )
        Spacer(Modifier.height(Space.m))
        RecordButton(
            recording = phase == VoicePhase.Listening,
            enabled = phase != VoicePhase.Thinking,
            onClick = onRecordTap,
        )
        Spacer(Modifier.height(Space.s))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            val canReplay = phase == VoicePhase.Idle || phase == VoicePhase.Speaking || phase == VoicePhase.YourTurn
            QuietButton("Replay question", { session.replayQuestion() }, icon = PrepIcons.Replay, enabled = canReplay)
            QuietButton("Type instead", onTypeInstead, icon = PrepIcons.Keyboard, enabled = canReplay)
        }
    }
}

@Composable
private fun RecordButton(recording: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val c = Prep.colors
    val size by animateDpAsState(if (recording) 26.dp else 30.dp, tween(260, easing = Motion.decelerate), label = "recSize")
    val corner by animateDpAsState(if (recording) 6.dp else 15.dp, tween(260, easing = Motion.decelerate), label = "recCorner")
    Box(
        modifier = Modifier
            .size(76.dp)
            .clip(CircleShape)
            .border(1.5.dp, c.text.copy(alpha = if (enabled) 0.85f else 0.25f), CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = if (recording) "Stop recording" else "Start recording" },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(size).clip(RoundedCornerShape(corner)).background(c.recording.copy(alpha = if (enabled) 1f else 0.35f)))
    }
}

private fun formatClock(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    return "%d:%02d".format(total / 60, total % 60)
}
