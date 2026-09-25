package app.prepsuite.android.feature.practice

import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.prepsuite.android.R
import app.prepsuite.android.data.QuestionBank
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.designsystem.GlassCard
import app.prepsuite.android.designsystem.Hairline
import app.prepsuite.android.designsystem.HomePalette
import app.prepsuite.android.designsystem.LocalPrepColors
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcon
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.RadioRow
import app.prepsuite.android.designsystem.Radius
import app.prepsuite.android.designsystem.SectionLabel
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.TopBar
import app.prepsuite.android.designsystem.glassSurface
import app.prepsuite.android.feature.voice.PresenceVideo

private fun lengthLabel(length: Int) = if (length == 1) "1 question" else "$length questions"

// Home stage geometry: the presence sits at the top and the question panel slides over its lower edge.
private val PresenceSize = 232.dp
private val PanelOverlap = 72.dp
private val FrostRadius = 8.dp

// Blurring spreads the thin gold rings thin; lift the frosted copy so they still read as light.
private val FrostLift = ColorFilter.colorMatrix(ColorMatrix().apply { setToScale(1.6f, 1.6f, 1.6f, 1f) })

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
    val question = remember(role) { QuestionBank.starter(role) }
    val libraryCount = remember(role) { QuestionBank.forRole(role).size }

    CompositionLocalProvider(LocalPrepColors provides HomePalette) {
        val c = Prep.colors
        // Opaque base inside the tab, so the Screen-blended presence always has a backdrop to light,
        // including while the tab or the route cross-fades.
        Column(Modifier.fillMaxSize().background(c.bg).verticalScroll(rememberScrollState())) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = Space.gutter, end = Space.s),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("PrepSuite", style = Prep.type.wordmark, color = c.text, modifier = Modifier.weight(1f))
                Box(
                    Modifier.size(48.dp).clip(CircleShape)
                        .clickable(role = Role.Button, onClick = onSettings)
                        .semantics { contentDescription = "Settings" },
                    contentAlignment = Alignment.Center,
                ) {
                    PrepIcon(PrepIcons.Sliders, null, c.text2, size = 22.dp)
                }
            }

            Spacer(Modifier.height(Space.s))
            PresenceStage {
                Text(question.text, style = Prep.type.question, color = c.text, modifier = Modifier.semantics { heading() })
                Spacer(Modifier.height(Space.m))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.s)) {
                    PrepIcon(if (quiet) PrepIcons.SpeakerOff else PrepIcons.Clock, null, c.text2, size = 18.dp)
                    Text(
                        if (quiet) "Question audio is off. Record when you're ready." else "Up to 2 minutes per answer. No rush to begin.",
                        style = Prep.type.meta,
                        color = c.text2,
                    )
                }
                Spacer(Modifier.height(Space.xxl))
                PrimaryButton("Start practice", onStart)
                Spacer(Modifier.height(Space.s))
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(Radius.chip))
                        .clickable(role = Role.Button, onClickLabel = "Change session", onClick = onSetup),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("${role.label} · ${lengthLabel(length)}", style = Prep.type.meta, color = c.text3, modifier = Modifier.weight(1f))
                    Text("Change", style = Prep.type.label, color = c.text)
                }
            }

            Text(
                "More ways to prepare",
                style = Prep.type.titleM,
                color = c.text,
                modifier = Modifier
                    .padding(start = Space.gutter, end = Space.gutter, top = Space.x4, bottom = Space.s)
                    .semantics { heading() },
            )
            HomeLink(PrepIcons.Write, "Quiet practice", "Write an answer first, then say it aloud.", onWrite)
            Hairline(Modifier.padding(start = Space.gutter + 24.dp + Space.l))
            HomeLink(PrepIcons.Layers, "Question library", "$libraryCount questions for your role.", onBrowseQuestions)
            Hairline(Modifier.padding(start = Space.gutter + 24.dp + Space.l))
            HomeLink(PrepIcons.User, "Your profile", "Your role and experience.", onProfile)
            Spacer(Modifier.height(Space.xxl))
        }
    }
}

/**
 * The gold presence with the question panel set over its lower edge. The panel is the only glass on
 * Home: it redraws the presence layer behind itself, blurred, then tints it, so the rings under it read
 * as softened light instead of a flat translucent fill. Below API 31 it falls back to a solid tint.
 */
@Composable
private fun PresenceStage(panel: @Composable ColumnScope.() -> Unit) {
    val c = Prep.colors
    val presence = rememberGraphicsLayer()
    val frost = rememberGraphicsLayer()
    val canBlur = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    val panelTop = PresenceSize - PanelOverlap
    val shape = RoundedCornerShape(Radius.sheet)

    Box(Modifier.fillMaxWidth()) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(PresenceSize)
                .drawWithContent {
                    presence.record { this@drawWithContent.drawContent() }
                    drawLayer(presence)
                },
            contentAlignment = Alignment.Center,
        ) {
            // The warm light the presence casts into the room. It may spill past the box so it also
            // falls behind the panel, and it has faded out before the top of the screen.
            Canvas(Modifier.matchParentSize()) {
                val r = size.minDimension * 0.9f
                drawCircle(
                    Brush.radialGradient(
                        0f to c.accent.copy(alpha = 0.18f),
                        0.5f to c.accent.copy(alpha = 0.06f),
                        1f to Color.Transparent,
                        center = center,
                        radius = r,
                    ),
                    radius = r,
                )
            }
            PresenceVideo(video = R.raw.presence_loop, level = { 0f }, modifier = Modifier.size(PresenceSize))
        }

        Column(
            Modifier
                .padding(top = panelTop)
                .padding(horizontal = Space.gutter)
                .fillMaxWidth()
                .clip(shape)
                .drawBehind {
                    if (canBlur) {
                        // Resolve px first: reading density inside record {} recurses in Compose.
                        val blur = FrostRadius.toPx()
                        val dx = Space.gutter.toPx()
                        val dy = panelTop.toPx()
                        frost.renderEffect = BlurEffect(blur, blur, TileMode.Clamp)
                        frost.colorFilter = FrostLift
                        frost.record {
                            drawRect(c.bg)
                            translate(-dx, -dy) { drawLayer(presence) }
                        }
                        drawLayer(frost)
                        drawRect(c.glassBg)
                    } else {
                        drawRect(c.glassBg.copy(alpha = 0.92f))
                    }
                    // A 1dp light catch on the top edge that runs into the corners and fades out.
                    drawOutline(
                        shape.createOutline(size, layoutDirection, this),
                        Brush.verticalGradient(0f to c.cardHighlight, 1f to Color.Transparent, endY = Radius.sheet.toPx()),
                        style = Stroke(2.dp.toPx()),
                    )
                }
                .padding(start = Space.xxl, end = Space.xxl, top = Space.xxl, bottom = Space.m),
            content = panel,
        )
    }
}

@Composable
private fun HomeLink(icon: ImageVector, title: String, meta: String, onClick: () -> Unit) {
    val c = Prep.colors
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = Space.gutter, vertical = Space.m),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.l),
    ) {
        PrepIcon(icon, null, c.text2)
        Column(Modifier.weight(1f)) {
            Text(title, style = Prep.type.bodyL.copy(fontWeight = FontWeight(500)), color = c.text)
            Text(meta, style = Prep.type.meta, color = c.text3)
        }
        PrepIcon(PrepIcons.Chevron, null, c.text3, size = 18.dp)
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
