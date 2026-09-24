package app.prepsuite.android.feature.quiet

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.prepsuite.android.data.ExerciseTemplate
import app.prepsuite.android.data.Exercises
import app.prepsuite.android.data.Pending
import app.prepsuite.android.data.PracticeMode
import app.prepsuite.android.data.QuestionBank
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.data.SessionSummary
import app.prepsuite.android.designsystem.GlassCard
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcon
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.QuietButton
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.Tag
import app.prepsuite.android.designsystem.TextInput
import app.prepsuite.android.designsystem.TopBar
import app.prepsuite.android.prepApp
import java.util.UUID

private val DraftListSaver = listSaver<SnapshotStateList<String>, String>(
    save = { it.toList() },
    restore = { it.toMutableStateList() },
)

@Composable
fun QuietPracticeScreen(onVoice: (String) -> Unit = {}) {
    val app = prepApp()
    val c = Prep.colors
    val history by app.history.items.collectAsStateWithLifecycle()
    var activeIndex by rememberSaveable { mutableIntStateOf(-1) }
    var reviewing by rememberSaveable { mutableStateOf(false) }
    val responses = rememberSaveable(saver = DraftListSaver) { mutableStateListOf("", "") }
    val checks = rememberSaveable(saver = DraftListSaver) { mutableStateListOf("", "") }
    val savedIds = rememberSaveable(saver = DraftListSaver) { mutableStateListOf("", "") }
    val savedResponses = rememberSaveable(saver = DraftListSaver) { mutableStateListOf("", "") }

    fun goBack() {
        if (reviewing) reviewing = false else activeIndex = -1
    }
    BackHandler(activeIndex >= 0) { goBack() }

    if (activeIndex < 0) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = Space.gutter),
            verticalArrangement = Arrangement.spacedBy(Space.l),
        ) {
            Spacer(Modifier.height(Space.s))
            Text("Quiet practice", style = Prep.type.titleL, color = c.text)
            Text(
                "Find the words before you say them. A little space to shape a clearer answer.",
                style = Prep.type.bodyL, color = c.text2,
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.s)) {
                PrepIcon(PrepIcons.Write, null, c.accent, size = 18.dp)
                Text("Two short exercises · No microphone", style = Prep.type.meta, color = c.text2)
            }
            Spacer(Modifier.height(Space.xs))
            Exercises.starters.forEachIndexed { index, exercise ->
                val hasDraft = responses[index].isNotBlank()
                GlassCard(
                    Modifier.clip(RoundedCornerShape(24.dp))
                        .clickable(role = Role.Button) {
                            activeIndex = index
                            reviewing = false
                        },
                ) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(c.accentTint),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text("0${index + 1}", style = Prep.type.titleM, color = c.accent)
                        }
                        Spacer(Modifier.weight(1f))
                        Tag(if (hasDraft) "Draft ready" else "About 2 minutes", color = if (hasDraft) c.accent else c.text2)
                    }
                    Spacer(Modifier.height(Space.xl))
                    Text(exercise.template.label, style = Prep.type.questionM, color = c.text)
                    Spacer(Modifier.height(Space.s))
                    Text(
                        when (exercise.template) {
                            ExerciseTemplate.Shorten -> "Keep the useful details. Let the extra words go."
                            ExerciseTemplate.Contribution -> "Show what you did, even when it was a team effort."
                        },
                        style = Prep.type.body, color = c.text2,
                    )
                    Spacer(Modifier.height(Space.xl))
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.s)) {
                        Text(if (hasDraft) "Continue exercise" else "Start exercise", style = Prep.type.label, color = c.accent)
                        PrepIcon(PrepIcons.Chevron, null, c.accent, size = 18.dp)
                    }
                }
            }
            Text(
                "These starter exercises use example text. When you're ready, take the same question into voice practice.",
                style = Prep.type.body, color = c.text2,
                modifier = Modifier.padding(vertical = Space.s),
            )
            Spacer(Modifier.height(Space.xxl))
        }
        return
    }

    val exercise = Exercises.starters[activeIndex]
    val response = responses[activeIndex]
    val saved = response.isNotBlank() && savedResponses[activeIndex] == response &&
        history.any { it.id == savedIds[activeIndex] }
    val wordCount = response.trim().split(Regex("\\s+")).count { it.isNotBlank() }
    Column(Modifier.fillMaxSize()) {
        TopBar(if (reviewing) "Your revision" else exercise.template.label, onBack = { goBack() })
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState())
                .padding(horizontal = Space.gutter),
            verticalArrangement = Arrangement.spacedBy(Space.l),
        ) {
            Spacer(Modifier.height(Space.xs))
            Row(horizontalArrangement = Arrangement.spacedBy(Space.s)) {
                Tag(if (reviewing) "2 of 2 · Reflect" else "1 of 2 · Rewrite", color = c.accent)
                Tag("Quiet exercise", color = c.text2)
            }
            Text(
                if (reviewing) "A clearer way to say it." else exercise.instruction,
                style = Prep.type.questionM, color = c.text,
            )
            if (reviewing) {
                GlassCard {
                    Text("Your version", style = Prep.type.meta, color = c.accent)
                    Spacer(Modifier.height(Space.m))
                    Text(response, style = Prep.type.quote, color = c.text)
                    Spacer(Modifier.height(Space.m))
                    Text("$wordCount words", style = Prep.type.meta, color = c.text2)
                }
                GlassCard {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.s)) {
                        PrepIcon(PrepIcons.Write, null, c.accent, size = 20.dp)
                        Text("What to notice", style = Prep.type.titleM, color = c.text)
                    }
                    Spacer(Modifier.height(Space.m))
                    Text(checks[activeIndex], style = Prep.type.bodyL, color = c.text)
                    Spacer(Modifier.height(Space.m))
                    Text("A simple writing check, not an interview score.", style = Prep.type.meta, color = c.text2)
                }
                QuietButton("Edit my answer", { reviewing = false }, icon = PrepIcons.Write)
                GlassCard {
                    Text(if (saved) "Question saved for voice practice" else "Take it into voice practice", style = Prep.type.titleM, color = c.text)
                    Spacer(Modifier.height(Space.s))
                    Text(
                        if (saved) "Find this question in History → Retries while the app is open. Your spoken attempt is still waiting."
                        else "Save the linked question as a reminder, then try saying your answer when you have a quiet moment.",
                        style = Prep.type.body, color = c.text2,
                    )
                }
            } else {
                GlassCard {
                    Text("Example answer", style = Prep.type.meta, color = c.accent)
                    Spacer(Modifier.height(Space.m))
                    Text("“${exercise.excerpt}”", style = Prep.type.quote, color = c.text)
                }
                Column(verticalArrangement = Arrangement.spacedBy(Space.s)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Your version", style = Prep.type.label, color = c.text)
                        Text("$wordCount words", style = Prep.type.meta, color = c.text2)
                    }
                    TextInput(
                        value = response,
                        onValueChange = {
                            responses[activeIndex] = it
                            checks[activeIndex] = ""
                        },
                        placeholder = if (exercise.template == ExerciseTemplate.Contribution) "I…" else "Write a shorter version…",
                        minLines = 5,
                        modifier = Modifier.semantics { contentDescription = "Your version of the example answer" },
                    )
                    Text("Keep it honest. Only include details that are true.", style = Prep.type.meta, color = c.text2)
                }
            }
            Spacer(Modifier.height(Space.xl))
        }
        Column(Modifier.padding(horizontal = Space.gutter).padding(top = Space.s, bottom = Space.m)) {
            when {
                saved && reviewing -> {
                    PrimaryButton("Try it out loud", { onVoice(exercise.linkedQuestionId) })
                    QuietButton("Back to exercises", { activeIndex = -1; reviewing = false }, Modifier.align(Alignment.CenterHorizontally))
                }
                reviewing -> PrimaryButton("Save question for voice practice", {
                    val id = savedIds[activeIndex].ifEmpty { UUID.randomUUID().toString() }
                    app.history.upsert(
                        SessionSummary(
                            id = id,
                            questionText = QuestionBank.byId(exercise.linkedQuestionId).text,
                            role = RolePack.General,
                            mode = PracticeMode.Quiet,
                            attempts = 0,
                            hasRetry = false,
                            completed = true,
                            pending = Pending.RetryWaiting,
                            createdAt = System.currentTimeMillis(),
                        ),
                    )
                    savedIds[activeIndex] = id
                    savedResponses[activeIndex] = response
                })
                else -> PrimaryButton("Review my revision", {
                    checks[activeIndex] = Exercises.check(exercise, response).orEmpty()
                    reviewing = true
                }, enabled = response.isNotBlank())
            }
        }
    }
}
