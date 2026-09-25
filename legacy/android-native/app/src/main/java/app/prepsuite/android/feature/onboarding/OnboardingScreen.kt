package app.prepsuite.android.feature.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.designsystem.GlassCard
import app.prepsuite.android.designsystem.Hairline
import app.prepsuite.android.designsystem.IconAction
import app.prepsuite.android.designsystem.Motion
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcon
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.QuietButton
import app.prepsuite.android.designsystem.RadioRow
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.Tag
import app.prepsuite.android.designsystem.TextInput
import app.prepsuite.android.designsystem.glassSurface

@Composable
fun OnboardingScreen(onDone: (RolePack, String) -> Unit) {
    val c = Prep.colors
    var step by rememberSaveable { mutableIntStateOf(0) }
    var role by rememberSaveable { mutableStateOf(RolePack.General) }
    var notes by rememberSaveable { mutableStateOf("") }
    BackHandler(enabled = step > 0) { step-- }
    val progress by animateFloatAsState((step + 1) / 3f, tween(Motion.ENTER, easing = Motion.decelerate), label = "progress")

    Column(Modifier.fillMaxSize().background(c.bg).windowInsetsPadding(WindowInsets.safeDrawing).imePadding()) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = Space.gutter),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.m),
        ) {
            if (step > 0) IconAction(PrepIcons.Back, "Previous step", { step-- })
            Text("PrepSuite", style = Prep.type.wordmark, color = c.text, modifier = Modifier.weight(1f))
            Text("${step + 1} / 3", style = Prep.type.meta, color = c.text2)
        }
        Box(Modifier.padding(horizontal = Space.gutter, vertical = Space.s).fillMaxWidth().height(3.dp).clip(CircleShape).background(c.line)) {
            Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(c.accent))
        }
        AnimatedContent(
            targetState = step,
            transitionSpec = {
                fadeIn(tween(Motion.ENTER, easing = Motion.decelerate)) togetherWith
                    fadeOut(tween(Motion.EXIT, easing = Motion.accelerate))
            },
            modifier = Modifier.weight(1f),
            label = "onboarding step",
        ) { currentStep ->
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = Space.l)) {
                when (currentStep) {
                    0 -> WelcomeStep()
                    1 -> RoleStep(role) { role = it }
                    else -> NotesStep(notes) { notes = it }
                }
            }
        }
        Column(Modifier.padding(horizontal = Space.gutter).padding(top = Space.s, bottom = Space.l)) {
            PrimaryButton(
                text = when (step) { 0 -> "Let's get started"; 1 -> "Continue"; else -> "Open my practice space" },
                onClick = { if (step < 2) step++ else onDone(role, notes.trim()) },
            )
            if (step == 2) QuietButton("Skip for now", onClick = { onDone(role, "") }, modifier = Modifier.align(Alignment.CenterHorizontally))
        }
    }
}

@Composable
private fun StepHeading(label: String, title: String, body: String) {
    Column(Modifier.padding(horizontal = Space.gutter).padding(top = Space.xl, bottom = Space.xl)) {
        Tag(label, color = Prep.colors.accent)
        Spacer(Modifier.height(Space.l))
        Text(title, style = Prep.type.question, color = Prep.colors.text, modifier = Modifier.semantics { heading() })
        Spacer(Modifier.height(Space.m))
        Text(body, style = Prep.type.bodyL, color = Prep.colors.text2)
    }
}

@Composable
private fun WelcomeStep() {
    val c = Prep.colors
    StepHeading(
        "A little preparation goes a long way",
        "Feel more like yourself in an interview.",
        "Practise saying what you mean, with real questions and room to try again.",
    )
    GlassCard(Modifier.padding(horizontal = Space.gutter)) {
        PromiseRow(PrepIcons.Mic, "Say it your way", "Read the question, take a moment, then record your answer.", c.accent)
        Hairline(Modifier.padding(vertical = Space.l))
        PromiseRow(PrepIcons.Replay, "Make room for a second take", "Listen back and practise the part you'd like to make clearer.", c.voiceWarm)
        Hairline(Modifier.padding(vertical = Space.l))
        PromiseRow(PrepIcons.Write, "Start quietly if you prefer", "Put your thoughts into words before saying them out loud.", c.accent)
    }
    Row(
        Modifier.padding(horizontal = Space.gutter, vertical = Space.xl),
        horizontalArrangement = Arrangement.spacedBy(Space.s),
    ) {
        PrepIcon(PrepIcons.Lock, null, c.text2, size = 18.dp)
        Text("Your recordings and practice notes stay on this device.", style = Prep.type.meta, color = c.text2, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun PromiseRow(icon: ImageVector, title: String, body: String, tint: Color) {
    val c = Prep.colors
    Row(horizontalArrangement = Arrangement.spacedBy(Space.m)) {
        Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(tint.copy(alpha = 0.1f)), contentAlignment = Alignment.Center) {
            PrepIcon(icon, null, tint, size = 20.dp)
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = Prep.type.titleM, color = c.text)
            Spacer(Modifier.height(Space.xs))
            Text(body, style = Prep.type.body, color = c.text2)
        }
    }
}

@Composable
private fun RoleStep(role: RolePack, onRole: (RolePack) -> Unit) {
    val c = Prep.colors
    StepHeading("Your starting point", "What are you preparing for?", "Choose a set of questions to begin with. You can change your role before any session.")
    Column(Modifier.padding(horizontal = Space.gutter).fillMaxWidth().glassSurface().selectableGroup()) {
        RolePack.entries.forEachIndexed { index, item ->
            RadioRow(
                title = item.label,
                selected = item == role,
                onClick = { onRole(item) },
                meta = if (item == RolePack.General) "Motivation, teamwork, problems and learning" else "Customer conversations, helping people and staying calm",
            )
            if (index < RolePack.entries.lastIndex) Hairline(Modifier.padding(horizontal = Space.l))
        }
    }
    GlassCard(Modifier.padding(horizontal = Space.gutter, vertical = Space.xl)) {
        Text("New to interviews? You're in the right place.", style = Prep.type.label, color = c.text)
        Spacer(Modifier.height(Space.s))
        Text("School, clubs, volunteering and everyday life all give you experiences worth talking about.", style = Prep.type.body, color = c.text2)
    }
    Text("Questions are currently in English.", style = Prep.type.meta, color = c.text2, modifier = Modifier.padding(horizontal = Space.gutter))
}

@Composable
private fun NotesStep(notes: String, onNotes: (String) -> Unit) {
    val c = Prep.colors
    StepHeading(
        "A few things to draw on",
        "You already have a story.",
        "Jot down an experience you might use in an answer. A small, real example is a good place to start.",
    )
    Column(Modifier.padding(horizontal = Space.gutter)) {
        Text("Your experience (optional)", style = Prep.type.label, color = c.text)
        Spacer(Modifier.height(Space.s))
        TextInput(
            value = notes,
            onValueChange = onNotes,
            placeholder = "I helped organise a school fundraiser. My job was…",
            minLines = 5,
        )
        Spacer(Modifier.height(Space.l))
        GlassCard {
            Text("Not sure what to write?", style = Prep.type.label, color = c.text)
            Spacer(Modifier.height(Space.s))
            Text("Think of a time you helped someone, worked with a group or figured something out.", style = Prep.type.body, color = c.text2)
        }
        Spacer(Modifier.height(Space.l))
        Row(horizontalArrangement = Arrangement.spacedBy(Space.s)) {
            PrepIcon(PrepIcons.Lock, null, c.text2, size = 18.dp)
            Text("Saved on this device. You can edit this in your profile.", style = Prep.type.meta, color = c.text2, modifier = Modifier.weight(1f))
        }
    }
}
