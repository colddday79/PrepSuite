package app.prepsuite.android.feature.practice

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.prepsuite.android.data.QuestionBank
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.designsystem.GlassCard
import app.prepsuite.android.designsystem.Hairline
import app.prepsuite.android.designsystem.IconAction
import app.prepsuite.android.designsystem.ListRow
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcon
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.RadioRow
import app.prepsuite.android.designsystem.SectionLabel
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.Tag
import app.prepsuite.android.designsystem.TopBar
import app.prepsuite.android.designsystem.glassSurface

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
    onBrowseQuestions: () -> Unit = {},
    onProfile: () -> Unit = {},
) {
    val c = Prep.colors
    val question = remember(role) { QuestionBank.starter(role) }

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 68.dp).padding(horizontal = Space.gutter),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.m),
        ) {
            Text("PrepSuite", style = Prep.type.wordmark, color = c.text, modifier = Modifier.weight(1f))
            IconAction(PrepIcons.Sliders, "Settings", onSettings)
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Space.gutter),
            verticalArrangement = Arrangement.spacedBy(Space.l),
        ) {
            Column(Modifier.padding(top = Space.s, bottom = Space.s)) {
                Text("Find your words.", style = Prep.type.titleL, color = c.text, modifier = Modifier.semantics { heading() })
                Spacer(Modifier.height(Space.xs))
                Text("A little practice, at your pace.", style = Prep.type.bodyL, color = c.text2)
            }

            GlassCard {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Space.m),
                ) {
                    Box(
                        Modifier.size(48.dp).clip(CircleShape).background(c.accentTint),
                        contentAlignment = Alignment.Center,
                    ) {
                        PrepIcon(PrepIcons.Mic, null, c.accent, size = 22.dp)
                    }
                    Column(Modifier.weight(1f)) {
                        Text("VOICE PRACTICE", style = Prep.type.meta.copy(fontWeight = FontWeight.SemiBold), color = c.accent)
                        Text("${role.short} · ${lengthLabel(length)}", style = Prep.type.meta, color = c.text2)
                    }
                }
                Spacer(Modifier.height(Space.xl))
                Tag(question.skill.label, color = c.voiceWarm)
                Spacer(Modifier.height(Space.m))
                Text(question.text, style = Prep.type.question, color = c.text, modifier = Modifier.semantics { heading() })
                Spacer(Modifier.height(Space.l))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Space.s),
                ) {
                    PrepIcon(if (quiet) PrepIcons.SpeakerOff else PrepIcons.Clock, null, c.text2, size = 18.dp)
                    Text(
                        if (quiet) "Question audio is off. Record when you're ready." else "Up to 2 minutes per answer. No rush to begin.",
                        style = Prep.type.meta,
                        color = c.text2,
                        modifier = Modifier.weight(1f),
                    )
                }
                Spacer(Modifier.height(Space.l))
                PrimaryButton("Start practice", onStart)
            }

            PracticeGroup {
                ListRow(
                    title = "Make it your session",
                    meta = "${role.label} · ${lengthLabel(length)}",
                    leading = PrepIcons.Sliders,
                    onClick = onSetup,
                )
            }

            Text("More ways to prepare", style = Prep.type.titleM, color = c.text, modifier = Modifier.padding(top = Space.s).semantics { heading() })
            PracticeGroup {
                ListRow(
                    title = "Quiet practice",
                    meta = "Shape an answer in writing, then try it aloud.",
                    leading = PrepIcons.Write,
                    onClick = onWrite,
                )
                Hairline(Modifier.padding(horizontal = Space.l))
                ListRow(
                    title = "Question library",
                    meta = "Explore ${QuestionBank.forRole(role).size} questions for your role.",
                    leading = PrepIcons.Layers,
                    onClick = onBrowseQuestions,
                )
            }
            PracticeGroup {
                ListRow(
                    title = "Your profile",
                    meta = "Keep your role and experience close at hand.",
                    leading = PrepIcons.User,
                    onClick = onProfile,
                )
            }
            Spacer(Modifier.height(Space.s))
        }
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
        TopBar(title = "Session setup", onBack = onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Column(Modifier.padding(horizontal = Space.gutter, vertical = Space.l)) {
                Text("A session that fits.", style = Prep.type.titleL, color = c.text, modifier = Modifier.semantics { heading() })
                Spacer(Modifier.height(Space.s))
                Text("Choose a role and how much you'd like to practise.", style = Prep.type.bodyL, color = c.text2)
            }

            SectionLabel("Preparing for")
            PracticeGroup(Modifier.padding(horizontal = Space.gutter).selectableGroup()) {
                RolePack.entries.forEachIndexed { index, item ->
                    RadioRow(
                        title = item.label,
                        selected = item == role,
                        onClick = { onRole(item) },
                        meta = if (item == RolePack.General) "Motivation, teamwork and problem solving" else "Helping people and handling busy moments",
                    )
                    if (index < RolePack.entries.lastIndex) Hairline(Modifier.padding(horizontal = Space.l))
                }
            }

            SectionLabel("How much time do you have?")
            PracticeGroup(Modifier.padding(horizontal = Space.gutter).selectableGroup()) {
                RadioRow("One question", length == 1, { onLength(1) }, "A small step. Focus on a single answer.")
                Hairline(Modifier.padding(horizontal = Space.l))
                RadioRow("Three questions", length == 3, { onLength(3) }, "A longer session with a little more variety.")
            }

            GlassCard(Modifier.padding(horizontal = Space.gutter, vertical = Space.xl)) {
                Row(horizontalArrangement = Arrangement.spacedBy(Space.m)) {
                    PrepIcon(PrepIcons.Mic, null, c.accent, size = 22.dp)
                    Column(Modifier.weight(1f)) {
                        Text("Your own words, your own pace", style = Prep.type.label, color = c.text)
                        Spacer(Modifier.height(Space.xs))
                        Text("Each answer can be up to two minutes. You can read the question before recording and listen back afterwards.", style = Prep.type.body, color = c.text2)
                    }
                }
            }
        }
        PrimaryButton("Start practice", onStart, Modifier.padding(Space.gutter))
    }
}

@Composable
private fun PracticeGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().glassSurface(), content = content)
}
