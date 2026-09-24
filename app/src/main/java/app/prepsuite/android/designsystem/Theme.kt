package app.prepsuite.android.designsystem

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.interaction.FocusInteraction
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.prepsuite.android.R
import kotlinx.coroutines.launch

@Immutable
data class PrepColors(
    val bg: Color,
    val surface1: Color,
    val surface2: Color,
    val line: Color,
    val lineStrong: Color,
    val text: Color,
    val text2: Color,
    val text3: Color,
    val accent: Color,
    val accentTint: Color,
    val danger: Color,
    val pending: Color,
    val recording: Color,
    val voiceCanvas: Color,
    val voiceField: Color,
    val voiceFaint: Color,
    val voiceCool: Color,
    val voiceWarm: Color,
    val glassBorder: Color = Color(0x26FFFFFF),
    val glassBg: Color = Color(0xD9161B23),
    val cardHighlight: Color = Color(0x0DFFFFFF),
)

// Obsidian surfaces, cool daylight accents and warm highlights for the voice presence.
val DarkPalette = PrepColors(
    bg = Color(0xFF0A0B0E),
    surface1 = Color(0xFF13151B),
    surface2 = Color(0xFF1B1E27),
    line = Color(0xFF222634),
    lineStrong = Color(0xFF384054),
    text = Color(0xFFF8FAFC),
    text2 = Color(0xFFB1BBC9),
    text3 = Color(0xFF8D9BAE),
    accent = Color(0xFF83D5FA),
    accentTint = Color(0xFF0C2B3F),
    danger = Color(0xFFF87171),
    pending = Color(0xFFE9C578),
    recording = Color(0xFFFB7185),
    voiceCanvas = Color(0xFF07080B),
    voiceField = Color(0xFF0D1117),
    voiceFaint = Color(0xFF384556),
    voiceCool = Color(0xFF7DD3FC),
    voiceWarm = Color(0xFFE9C578),
    glassBorder = Color(0x26FFFFFF),
    glassBg = Color(0xD9161B23),
    cardHighlight = Color(0x0DFFFFFF),
)

@OptIn(ExperimentalTextApi::class)
private fun mona(weight: Int, width: Float = 100f) = Font(
    resId = R.font.mona_sans,
    weight = FontWeight(weight),
    variationSettings = FontVariation.Settings(FontVariation.weight(weight), FontVariation.width(width)),
)

private val MonaSans = FontFamily(mona(300), mona(400), mona(500), mona(600), mona(700))
private val MonaSansNarrow = FontFamily(mona(300, 88f), mona(400, 88f), mona(500, 88f))

@Immutable
data class PrepType(
    val question: TextStyle,
    val questionM: TextStyle,
    val quote: TextStyle,
    val titleL: TextStyle,
    val titleM: TextStyle,
    val bodyL: TextStyle,
    val body: TextStyle,
    val label: TextStyle,
    val meta: TextStyle,
    val timer: TextStyle,
    val wordmark: TextStyle,
)

// Clean, high-legibility typographic hierarchy powered by Mona Sans
val PrepTypography = PrepType(
    question = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(500),
        fontSize = 25.sp,
        lineHeight = 34.sp,
        letterSpacing = (-0.02).em,
    ),
    questionM = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(500),
        fontSize = 20.sp,
        lineHeight = 28.sp,
        letterSpacing = (-0.01).em,
    ),
    quote = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(400),
        fontSize = 16.sp,
        lineHeight = 25.sp,
        letterSpacing = 0.005.em,
    ),
    titleL = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(700),
        fontSize = 28.sp,
        lineHeight = 35.sp,
        letterSpacing = (-0.02).em,
    ),
    titleM = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(600),
        fontSize = 17.sp,
        lineHeight = 23.sp,
        letterSpacing = (-0.01).em,
    ),
    bodyL = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(400),
        fontSize = 16.sp,
        lineHeight = 24.sp,
    ),
    body = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(400),
        fontSize = 15.sp,
        lineHeight = 23.sp,
        letterSpacing = 0.005.em,
    ),
    label = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(600),
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.01.em,
    ),
    meta = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(500),
        fontSize = 13.sp,
        lineHeight = 18.sp,
        letterSpacing = 0.01.em,
    ),
    timer = TextStyle(
        fontFamily = MonaSansNarrow,
        fontWeight = FontWeight(400),
        fontSize = 22.sp,
        lineHeight = 26.sp,
        fontFeatureSettings = "tnum",
    ),
    wordmark = TextStyle(
        fontFamily = MonaSans,
        fontWeight = FontWeight(700),
        fontSize = 18.sp,
        lineHeight = 23.sp,
        letterSpacing = (-0.02).em,
    ),
)

object Space {
    val xxs = 2.dp
    val xs = 4.dp
    val s = 8.dp
    val m = 12.dp
    val l = 16.dp
    val xl = 20.dp
    val xxl = 24.dp
    val x3 = 32.dp
    val x4 = 40.dp
    val x5 = 48.dp
    val gutter = 20.dp
}

object Radius {
    val chip = 12.dp
    val control = 16.dp
    val card = 24.dp
    val sheet = 28.dp
}

object Motion {
    val decelerate = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f)
    val accelerate = CubicBezierEasing(0.3f, 0f, 0.8f, 0.15f)
    val standard = CubicBezierEasing(0.2f, 0f, 0f, 1f)
    const val PRESS = 100
    const val FADE = 200
    const val ENTER = 300
    const val EXIT = 200
}

val LocalPrepColors = staticCompositionLocalOf { DarkPalette }
val LocalPrepType = staticCompositionLocalOf { PrepTypography }

object Prep {
    val colors: PrepColors
        @Composable @ReadOnlyComposable get() = LocalPrepColors.current
    val type: PrepType
        @Composable @ReadOnlyComposable get() = LocalPrepType.current
}

@Composable
fun PrepTheme(content: @Composable () -> Unit) {
    val c = DarkPalette
    val scheme = darkColorScheme(
        primary = c.text,
        onPrimary = c.bg,
        primaryContainer = c.accentTint,
        onPrimaryContainer = c.text,
        secondary = c.accent,
        onSecondary = c.bg,
        tertiary = c.accent,
        onTertiary = c.bg,
        background = c.bg,
        onBackground = c.text,
        surface = c.bg,
        onSurface = c.text,
        surfaceVariant = c.surface2,
        onSurfaceVariant = c.text2,
        surfaceTint = c.bg,
        outline = c.lineStrong,
        outlineVariant = c.line,
        error = c.danger,
        onError = c.bg,
        scrim = Color.Black,
        surfaceBright = c.surface2,
        surfaceDim = c.bg,
        surfaceContainerLowest = c.bg,
        surfaceContainerLow = c.surface1,
        surfaceContainer = c.surface1,
        surfaceContainerHigh = c.surface2,
        surfaceContainerHighest = c.surface2,
    )
    val type = PrepTypography
    MaterialTheme(
        colorScheme = scheme,
        typography = Typography(
            displayLarge = type.question,
            headlineLarge = type.titleL,
            headlineMedium = type.titleL,
            headlineSmall = type.questionM,
            titleLarge = type.titleM,
            titleMedium = type.titleM,
            titleSmall = type.label,
            bodyLarge = type.bodyL,
            bodyMedium = type.body,
            bodySmall = type.meta,
            labelLarge = type.label,
            labelMedium = type.meta,
            labelSmall = type.meta,
        ),
    ) {
        CompositionLocalProvider(
            LocalPrepColors provides c,
            LocalPrepType provides PrepTypography,
            LocalIndication provides PrepIndication,
            LocalContentColor provides c.text,
            LocalTextStyle provides PrepTypography.body,
            content = content,
        )
    }
}

// A quiet ink overlay instead of the stock ripple. Mid-grey reads on both light and dark fills.
private object PrepIndication : IndicationNodeFactory {
    override fun create(interactionSource: InteractionSource): DelegatableNode = PrepIndicationNode(interactionSource)
    override fun equals(other: Any?): Boolean = other === this
    override fun hashCode(): Int = javaClass.hashCode()
}

private class PrepIndicationNode(private val source: InteractionSource) : Modifier.Node(), DrawModifierNode {
    private val pressed = Animatable(0f)
    private val focused = Animatable(0f)

    override fun onAttach() {
        coroutineScope.launch {
            source.interactions.collect { interaction ->
                when (interaction) {
                    is PressInteraction.Press -> launch { pressed.animateTo(1f, tween(Motion.PRESS)) }
                    is PressInteraction.Release, is PressInteraction.Cancel -> launch { pressed.animateTo(0f, tween(Motion.FADE)) }
                    is FocusInteraction.Focus -> launch { focused.animateTo(1f, tween(Motion.PRESS)) }
                    is FocusInteraction.Unfocus -> launch { focused.animateTo(0f, tween(Motion.FADE)) }
                }
            }
        }
    }

    override fun ContentDrawScope.draw() {
        drawContent()
        val alpha = 0.12f * pressed.value + 0.08f * focused.value
        if (alpha > 0f) drawRect(Color(0xFF808080), alpha = alpha)
    }
}
