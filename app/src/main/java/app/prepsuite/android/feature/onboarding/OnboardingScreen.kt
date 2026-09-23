package app.prepsuite.android.feature.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.designsystem.Hairline
import app.prepsuite.android.designsystem.ListRow
import app.prepsuite.android.designsystem.Motion
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcon
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.QuietButton
import app.prepsuite.android.designsystem.RadioRow
import app.prepsuite.android.designsystem.SectionLabel
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.TextInput

@Composable
fun OnboardingScreen(onDone: (RolePack, String) -> Unit) {
    val c = Prep.colors
    var step by rememberSaveable { mutableIntStateOf(0) }
    var role by rememberSaveable { mutableStateOf(RolePack.General) }
    var notes by rememberSaveable { mutableStateOf("") }
    BackHandler(enabled = step > 0) { step-- }
    val progress by animateFloatAsState((step + 1) / 3f, tween(Motion.ENTER, easing = Motion.decelerate), label = "progress")

    Column(Modifier.fillMaxSize().background(c.bg).windowInsetsPadding(WindowInsets.safeDrawing).imePadding()) {
        Box(Modifier.padding(horizontal = Space.gutter, vertical = Space.m).fillMaxWidth().height(1.dp).background(c.line)) {
            Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(c.text))
        }
        Row(
            Modifier.fillMaxWidth().height(48.dp).padding(start = Space.gutter, end = Space.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("${step + 1} of 3", style = Prep.type.meta, color = c.text3, modifier = Modifier.weight(1f))
            if (step == 2) QuietButton("Skip", onClick = { onDone(role, "") })
        }
        AnimatedContent(
            targetState = step,
            transitionSpec = {
                val dir = if (targetState > initialState) 1 else -1
                (fadeIn(tween(Motion.ENTER, easing = Motion.decelerate)) +
                    slideInHorizontally(tween(Motion.ENTER, easing = Motion.decelerate)) { dir * it / 10 }) togetherWith
                    fadeOut(tween(Motion.EXIT, easing = Motion.accelerate))
            },
            modifier = Modifier.weight(1f),
            label = "step",
        ) { s ->
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                when (s) {
                    0 -> WelcomeStep()
                    1 -> RoleStep(role) { role = it }
                    else -> NotesStep(notes) { notes = it }
                }
            }
        }
        PrimaryButton(
            text = if (step < 2) "Continue" else "Start practising",
            onClick = { if (step < 2) step++ else onDone(role, notes.trim()) },
            modifier = Modifier.padding(Space.gutter),
        )
    }
}

@Composable
private fun StepHeading(title: String, body: String) {
    Column(Modifier.padding(horizontal = Space.gutter).padding(top = Space.x3, bottom = Space.xxl)) {
        Text(title, style = Prep.type.question, color = Prep.colors.text)
        Spacer(Modifier.height(Space.m))
        Text(body, style = Prep.type.bodyL, color = Prep.colors.text2)
    }
}

@Composable
private fun WelcomeStep() {
    StepHeading(
        "Practise one answer at a time.",
        "Answer real interview questions out loud, find the one moment that needs work, and try just that part again.",
    )
    Hairline(Modifier.padding(horizontal = Space.gutter))
    PromiseRow(PrepIcons.Speaker, "Questions are read aloud", "You can switch this off at any time.")
    PromiseRow(PrepIcons.Lock, "Recordings stay on this phone", "They're saved privately inside the app.")
    PromiseRow(PrepIcons.Shield, "Nothing is sent without asking", "Feedback only runs after you agree to it.")
}

@Composable
private fun PromiseRow(icon: ImageVector, title: String, body: String) {
    val c = Prep.colors
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Space.gutter, vertical = Space.l),
        horizontalArrangement = Arrangement.spacedBy(Space.l),
    ) {
        PrepIcon(icon, null, c.text2, size = 22.dp)
        Column {
            Text(title, style = Prep.type.bodyL, color = c.text)
            Text(body, style = Prep.type.body, color = c.text3)
        }
    }
    Hairline(Modifier.padding(horizontal = Space.gutter))
}

@Composable
private fun RoleStep(role: RolePack, onRole: (RolePack) -> Unit) {
    StepHeading("What are you preparing for?", "We'll start with questions that fit. You can change this later.")
    RolePack.entries.forEach { r ->
        RadioRow(
            title = r.label,
            selected = r == role,
            onClick = { onRole(r) },
            meta = if (r == RolePack.General) "Motivation, teamwork, problems, learning" else "Adds questions about helping customers",
        )
    }
    SectionLabel("Language")
    ListRow(title = "English", meta = "More languages later")
}

@Composable
private fun NotesStep(notes: String, onNotes: (String) -> Unit) {
    StepHeading(
        "Anything you'd like to draw on?",
        "Optional. Note a real experience — a club, volunteering, a school project, caring for someone. It stays on this phone.",
    )
    TextInput(
        value = notes,
        onValueChange = onNotes,
        placeholder = "For example: I helped run the stall at our school fundraiser.",
        minLines = 4,
        modifier = Modifier.padding(horizontal = Space.gutter),
    )
}
