package app.prepsuite.android.feature.quiet

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import app.prepsuite.android.data.Exercises
import app.prepsuite.android.data.Pending
import app.prepsuite.android.data.PracticeMode
import app.prepsuite.android.data.QuestionBank
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.data.SessionSummary
import app.prepsuite.android.designsystem.FilterChip
import app.prepsuite.android.designsystem.Notice
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.QuoteBlock
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.TextInput
import app.prepsuite.android.prepApp
import java.util.UUID

@Composable
fun QuietPracticeScreen() {
    val app = prepApp()
    val c = Prep.colors
    var templateIndex by rememberSaveable { mutableIntStateOf(0) }
    val exercise = Exercises.starters[templateIndex]
    var response by rememberSaveable(templateIndex) { mutableStateOf("") }
    var explanation by rememberSaveable(templateIndex) { mutableStateOf<String?>(null) }
    var saved by rememberSaveable(templateIndex) { mutableStateOf(false) }
    val buttonPadding = Modifier.padding(start = Space.gutter, end = Space.gutter, top = Space.s, bottom = Space.l)

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Text(
                "Quiet practice",
                style = Prep.type.titleL,
                color = c.text,
                modifier = Modifier.padding(horizontal = Space.gutter).padding(top = Space.xl),
            )
            Text(
                "Short written exercises for when you can't speak. Each one links back to a voice retry.",
                style = Prep.type.body,
                color = c.text2,
                modifier = Modifier.padding(horizontal = Space.gutter, vertical = Space.s),
            )
            Row(
                Modifier.padding(horizontal = Space.gutter, vertical = Space.s),
                horizontalArrangement = Arrangement.spacedBy(Space.s),
            ) {
                Exercises.starters.forEachIndexed { i, e ->
                    FilterChip(e.template.label, selected = i == templateIndex, onClick = { templateIndex = i })
                }
            }
            Text(
                "General exercise · not based on your answers yet",
                style = Prep.type.meta,
                color = c.text3,
                modifier = Modifier.padding(horizontal = Space.gutter).padding(top = Space.l, bottom = Space.s),
            )
            QuoteBlock(exercise.excerpt, Modifier.padding(horizontal = Space.gutter))
            Text(
                exercise.instruction,
                style = Prep.type.bodyL,
                color = c.text,
                modifier = Modifier.padding(horizontal = Space.gutter, vertical = Space.l),
            )
            TextInput(
                value = response,
                onValueChange = {
                    response = it
                    explanation = null
                    saved = false
                },
                placeholder = "Write your version…",
                minLines = 4,
                modifier = Modifier.padding(horizontal = Space.gutter),
            )
            explanation?.let {
                Spacer(Modifier.height(Space.l))
                Notice(it, Modifier.padding(horizontal = Space.gutter), color = c.text)
            }
            if (saved) {
                Text(
                    "Saved. It's waiting in History under Retries, ready for you to say out loud.",
                    style = Prep.type.meta,
                    color = c.accent,
                    modifier = Modifier.padding(horizontal = Space.gutter, vertical = Space.m),
                )
            }
            Spacer(Modifier.height(Space.l))
        }
        when {
            saved -> PrimaryButton(
                "Try the other exercise",
                { templateIndex = (templateIndex + 1) % Exercises.starters.size },
                buttonPadding,
            )
            explanation != null -> PrimaryButton(
                "Save for voice practice",
                {
                    app.history.upsert(
                        SessionSummary(
                            id = UUID.randomUUID().toString(),
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
                    saved = true
                },
                buttonPadding,
            )
            else -> PrimaryButton(
                "Check",
                { explanation = Exercises.check(exercise, response) },
                buttonPadding,
                enabled = response.isNotBlank(),
            )
        }
    }
}
