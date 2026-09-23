package app.prepsuite.android.feature.practice

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.prepsuite.android.data.QuestionBank
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.designsystem.Hairline
import app.prepsuite.android.designsystem.IconAction
import app.prepsuite.android.designsystem.ListRow
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.RadioRow
import app.prepsuite.android.designsystem.SectionLabel
import app.prepsuite.android.designsystem.SegmentedChoice
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.TopBar

private fun lengthLabel(length: Int) = if (length == 1) "1 question" else "$length questions"

@Composable
fun PracticeHomeScreen(
    role: RolePack,
    length: Int,
    quiet: Boolean,
    onStart: () -> Unit,
    onSetup: () -> Unit,
    onSettings: () -> Unit,
    onWrite: () -> Unit,
) {
    val c = Prep.colors
    val question = remember(role) { QuestionBank.starter(role) }
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().height(56.dp).padding(start = Space.gutter, end = Space.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("PrepSuite", style = Prep.type.wordmark, color = c.text, modifier = Modifier.weight(1f))
            IconAction(PrepIcons.Sliders, "Settings", onSettings)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Space.gutter)) {
            Spacer(Modifier.height(Space.x5))
            Text("Next question", style = Prep.type.meta, color = c.text3)
            Spacer(Modifier.height(Space.xs))
            Text("Starter · ${role.label}", style = Prep.type.meta, color = c.text2)
            Spacer(Modifier.height(Space.xl))
            Text(question.text, style = Prep.type.question, color = c.text)
            Spacer(Modifier.height(Space.l))
            Text(question.skill.label, style = Prep.type.meta, color = c.text3)
            Spacer(Modifier.height(Space.x3))
        }
        Hairline(Modifier.padding(horizontal = Space.gutter))
        ListRow(
            title = "Session",
            meta = if (quiet) "Quiet mode · questions shown, not read aloud" else null,
            value = "${role.short} · ${lengthLabel(length)}",
            onClick = onSetup,
        )
        ListRow(title = "Answer in writing instead", leading = PrepIcons.Write, onClick = onWrite)
        PrimaryButton(
            text = "Start practice",
            onClick = onStart,
            modifier = Modifier.padding(start = Space.gutter, end = Space.gutter, top = Space.s, bottom = Space.l),
        )
    }
}

@Composable
fun SessionSetupScreen(
    role: RolePack,
    length: Int,
    onRole: (RolePack) -> Unit,
    onLength: (Int) -> Unit,
    onBack: () -> Unit,
    onStart: () -> Unit,
) {
    val c = Prep.colors
    Column(Modifier.fillMaxSize().background(c.bg).windowInsetsPadding(WindowInsets.safeDrawing)) {
        TopBar(title = "Session", onBack = onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            SectionLabel("Role")
            RolePack.entries.forEach { r ->
                RadioRow(
                    title = r.label,
                    selected = r == role,
                    onClick = { onRole(r) },
                    meta = "${QuestionBank.forRole(r).size} reviewed questions",
                )
            }
            SectionLabel("Length")
            SegmentedChoice(
                options = listOf("1 question", "3 questions"),
                selected = if (length == 1) 0 else 1,
                onSelect = { onLength(if (it == 0) 1 else 3) },
                modifier = Modifier.padding(horizontal = Space.gutter),
            )
            Text(
                "Each answer can be up to two minutes.",
                style = Prep.type.meta,
                color = c.text3,
                modifier = Modifier.padding(horizontal = Space.gutter, vertical = Space.m),
            )
        }
        PrimaryButton("Start", onStart, Modifier.padding(Space.gutter))
    }
}
