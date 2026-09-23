package app.prepsuite.android.feature.feedback

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.prepsuite.android.data.Question
import app.prepsuite.android.designsystem.Notice
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcon
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.QuoteBlock
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.Tag
import app.prepsuite.android.designsystem.TopBar

@Composable
fun FeedbackScreen(question: Question, onBack: () -> Unit, onRetry: () -> Unit) {
    val c = Prep.colors
    Column(Modifier.fillMaxSize().background(c.bg).windowInsetsPadding(WindowInsets.safeDrawing)) {
        TopBar(title = "Feedback", onBack = onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Space.gutter)) {
            Notice("Preview. Feedback on your own answer appears here once the voice service is connected. The example below shows the layout.")
            Spacer(Modifier.height(Space.xxl))
            Text(question.text, style = Prep.type.questionM, color = c.text2)

            Heading("What worked", example = true)
            Text("You chose a real event and said why it mattered to the people involved.", style = Prep.type.bodyL, color = c.text)

            Heading("One thing to try")
            Text("Personal contribution", style = Prep.type.label, color = c.text)
            Spacer(Modifier.height(Space.s))
            QuoteBlock("We sorted everything out.")
            Row(
                Modifier.padding(vertical = Space.m),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Space.s),
            ) {
                PrepIcon(PrepIcons.Play, null, c.text3, size = 18.dp)
                Text("0:24–0:34 · Play this part", style = Prep.type.meta, color = c.text3)
            }
            Text("Why it matters", style = Prep.type.meta, color = c.text3)
            Text(
                "An interviewer wants to know what you did, not only what the group did.",
                style = Prep.type.body,
                color = c.text2,
            )
            Spacer(Modifier.height(Space.m))
            Text("Next step", style = Prep.type.meta, color = c.text3)
            Text("Say one thing you personally did, and what happened because of it.", style = Prep.type.body, color = c.text)
            Spacer(Modifier.height(Space.x3))
        }
        PrimaryButton("Retry this part", onRetry, Modifier.padding(Space.gutter))
    }
}

@Composable
private fun Heading(text: String, example: Boolean = false) {
    Spacer(Modifier.height(Space.xxl))
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.s)) {
        Text(text, style = Prep.type.titleM, color = Prep.colors.text)
        if (example) Tag("Example", color = Prep.colors.text3)
    }
    Spacer(Modifier.height(Space.s))
}
