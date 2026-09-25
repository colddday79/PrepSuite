package app.prepsuite.android.feature.pages

import android.media.MediaPlayer
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.prepsuite.android.data.QuestionBank
import app.prepsuite.android.designsystem.*
import java.io.File

/** UI flow payload. Audio remains the immutable file produced by the recorder. */
data class AnswerSnapshot(val questionId: String, val audioPath: String?, val durationMs: Long, val notes: String = "")

@Composable
fun AnswerReviewScreen(answer: AnswerSnapshot, onBack: () -> Unit, onContinue: (AnswerSnapshot) -> Unit) {
    var text by rememberSaveable(answer.audioPath) { mutableStateOf(answer.notes) }
    val playback = rememberAnswerPlayback()
    PageLayout("Review your answer", onBack, footer = {
        PrimaryButton("Continue", { onContinue(answer.copy(notes = text.trim())) })
    }) {
        PageIntro("Your answer", "Listen back.\nNotice one thing.", "Your recording is saved on this phone. Take a moment before your next attempt.")
        GlassPanel {
            Tag(QuestionBank.byId(answer.questionId).skill.label)
            Spacer(Modifier.height(Space.m))
            Text(QuestionBank.byId(answer.questionId).text, style = Prep.type.questionM)
            Spacer(Modifier.height(Space.l))
            RecordingControl("Original answer", answer, playback)
        }
        GlassPanel {
            Text("Your notes", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.s))
            Text("Automatic transcription is not available yet. You can type what you said or note the part you want to improve.", style = Prep.type.body, color = Prep.colors.text2)
            Spacer(Modifier.height(Space.l))
            TextInput(text, { text = it }, "What did you say?", minLines = 5)
        }
        Notice("Nothing is sent for analysis in this preview. Your notes stay in this practice flow until you leave it.")
    }
}

@Composable
fun ReflectionScreen(answer: AnswerSnapshot, onBack: () -> Unit, onRetry: () -> Unit, onExample: () -> Unit, onFinish: () -> Unit) {
    val playback = rememberAnswerPlayback()
    PageLayout("Your next step", onBack, footer = { PrimaryButton("Try another take", onRetry) }) {
        PageIntro("Small steps count", "Make your part clear.", "Listen to your answer and choose one thing to work on next.")
        GlassPanel {
            RecordingControl("Your recording", answer, playback)
            if (answer.notes.isNotBlank()) {
                Spacer(Modifier.height(Space.l))
                QuoteBlock(answer.notes)
            }
        }
        GlassPanel {
            Tag("Self-review", color = Prep.colors.accent)
            Spacer(Modifier.height(Space.m))
            Text("What would you keep?", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.s))
            Text("Look for a moment that answers the question directly.", color = Prep.colors.text2)
            Spacer(Modifier.height(Space.l))
            Hairline()
            Spacer(Modifier.height(Space.l))
            Text("What would you make clearer?", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.s))
            Text("If it fits the question, say what you personally did and what happened next. Use only your real experience.", color = Prep.colors.text2)
        }
        Notice("Personalised feedback is not available in this build. These are general reflection prompts, not an assessment of your answer.")
        QuietButton("Explore example feedback", onExample, icon = PrepIcons.Chevron)
        QuietButton("Finish for now", onFinish, icon = PrepIcons.Check)
    }
}

@Composable
fun RetryPlanScreen(answer: AnswerSnapshot, onBack: () -> Unit, onRecord: () -> Unit) {
    PageLayout("Try again", onBack, footer = { PrimaryButton("Record a new take", onRecord) }) {
        PageIntro("One thing at a time", "Keep the original.\nTry a clearer take.", "You can answer the whole question or practise just the part you want to change.")
        GlassPanel {
            Tag("Original question")
            Spacer(Modifier.height(Space.m))
            Text(QuestionBank.byId(answer.questionId).text, style = Prep.type.questionM)
        }
        GlassPanel {
            Text("Before you record", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.m))
            Text("01   Choose one point to make clearer.", style = Prep.type.bodyL)
            Spacer(Modifier.height(Space.l))
            Text("02   Use details from your own experience.", style = Prep.type.bodyL)
            Spacer(Modifier.height(Space.l))
            Text("03   Listen to the two takes side by side.", style = Prep.type.bodyL)
        }
        Notice("The original recording stays unchanged. A short retry is saved separately and is never spliced into your answer.")
    }
}

@Composable
fun ComparisonScreen(original: AnswerSnapshot, retry: AnswerSnapshot, onBack: () -> Unit, onAgain: () -> Unit, onDone: () -> Unit) {
    val playback = rememberAnswerPlayback()
    PageLayout("Compare your takes", onBack, footer = { PrimaryButton("Finish practice", onDone) }) {
        PageIntro("Listen for the difference", "Same question.\nA new way to say it.", "Play each recording in turn. Decide which parts you want to keep.")
        Text(QuestionBank.byId(original.questionId).text, style = Prep.type.questionM)
        GlassPanel {
            RecordingControl("Original", original, playback)
            if (original.notes.isNotBlank()) {
                Spacer(Modifier.height(Space.m)); QuoteBlock(original.notes)
            }
        }
        GlassPanel {
            RecordingControl("New take", retry, playback)
            if (retry.notes.isNotBlank()) {
                Spacer(Modifier.height(Space.m)); QuoteBlock(retry.notes)
            }
        }
        GlassPanel {
            Text("What changed?", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.s))
            Text("Is your answer more relevant? Is your own contribution clearer? A shorter answer is not automatically a better one.", color = Prep.colors.text2)
        }
        QuietButton("Try one more take", onAgain, icon = PrepIcons.Replay)
    }
}

@Stable
class AnswerPlayback {
    var activePath by mutableStateOf<String?>(null)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    private var player: MediaPlayer? = null
    fun toggle(path: String?) {
        if (path == activePath && path != null) { stop(); return }
        stop()
        if (path == null || !File(path).exists()) { error = "This recording is no longer available."; return }
        error = null
        var candidate: MediaPlayer? = null
        runCatching {
            candidate = MediaPlayer().also { media ->
                media.setDataSource(path)
                media.setOnCompletionListener { stop() }
                media.setOnErrorListener { _, _, _ -> stop(); error = "This recording could not be played."; true }
                media.prepare()
                media.start()
            }
            player = candidate
            activePath = path
        }.onFailure { candidate?.release(); error = "This recording could not be played." }
    }
    fun stop() {
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
        activePath = null
    }
}

@Composable
fun rememberAnswerPlayback(): AnswerPlayback {
    val playback = remember { AnswerPlayback() }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(playback, owner) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) playback.stop() }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer); playback.stop() }
    }
    return playback
}

@Composable
private fun RecordingControl(title: String, answer: AnswerSnapshot, playback: AnswerPlayback) {
    val playing = playback.activePath == answer.audioPath && answer.audioPath != null
    val available = answer.audioPath?.let { File(it).exists() } == true
    Column {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.s)) {
            Column(Modifier.weight(1f)) {
                Text(title, style = Prep.type.titleM)
                Spacer(Modifier.height(4.dp))
                Text(if (available) "${formatDuration(answer.durationMs)} · On this phone" else "Recording unavailable", style = Prep.type.meta, color = Prep.colors.text2)
            }
            QuietButton(if (playing) "Stop" else "Play", { playback.toggle(answer.audioPath) }, icon = if (playing) PrepIcons.Pause else PrepIcons.Play, enabled = available)
        }
        playback.error?.let { Text(it, color = Prep.colors.danger, style = Prep.type.meta) }
    }
}

fun formatDuration(ms: Long): String = "%d:%02d".format(ms / 60_000, (ms / 1000) % 60)
