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
)

val DarkPalette = PrepColors(
    bg = Color(0xFF0E0F0F),
    surface1 = Color(0xFF161817),
    surface2 = Color(0xFF1E201F),
    line = Color(0xFF2A2D2B),
    lineStrong = Color(0xFF6B706C),
    text = Color(0xFFECEAE5),
    text2 = Color(0xFFA8ACA8),
    text3 = Color(0xFF8A8F8B),
    accent = Color(0xFF74C7B8),
    accentTint = Color(0xFF253431),
    danger = Color(0xFFF2998C),
    pending = Color(0xFFE3BA6A),
    recording = Color(0xFFFF7A66),
    voiceCanvas = Color(0xFF07090A),
    voiceField = Color(0xFF0C1517),
    voiceFaint = Color(0xFF4B575E),
    voiceCool = Color(0xFFA9E3E8),
    voiceWarm = Color(0xFFFFB870),
)

@OptIn(ExperimentalTextApi::class)
private fun mona(weight: Int, width: Float = 100f) = Font(
    resId = R.font.mona_sans,
    weight = FontWeight(weight),
    variationSettings = FontVariation.Settings(FontVariation.weight(weight), FontVariation.width(width)),
)

@OptIn(ExperimentalTextApi::class)
private fun newsreader(weight: Int, opticalSize: Float) = Font(
    resId = R.font.newsreader,
    weight = FontWeight(weight),
    variationSettings = FontVariation.Settings(
        FontVariation.weight(weight),
        FontVariation.Setting("opsz", opticalSize),
    ),
)

private val MonaSans = FontFamily(mona(300), mona(400), mona(500), mona(600))
private val MonaSansNarrow = FontFamily(mona(300, 88f), mona(400, 88f))
private val Newsreader = FontFamily(newsreader(300, 36f), newsreader(400, 18f))

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

val PrepTypography = PrepType(
    question = TextStyle(fontFamily = Newsreader, fontWeight = FontWeight(300), fontSize = 30.sp, lineHeight = 38.sp, letterSpacing = (-0.01).em),
    questionM = TextStyle(fontFamily = Newsreader, fontWeight = FontWeight(300), fontSize = 22.sp, lineHeight = 30.sp),
    quote = TextStyle(fontFamily = Newsreader, fontWeight = FontWeight(400), fontSize = 19.sp, lineHeight = 27.sp),
    titleL = TextStyle(fontFamily = MonaSans, fontWeight = FontWeight(600), fontSize = 24.sp, lineHeight = 30.sp, letterSpacing = (-0.01).em),
    titleM = TextStyle(fontFamily = MonaSans, fontWeight = FontWeight(500), fontSize = 18.sp, lineHeight = 24.sp),
    bodyL = TextStyle(fontFamily = MonaSans, fontWeight = FontWeight(400), fontSize = 17.sp, lineHeight = 26.sp),
    body = TextStyle(fontFamily = MonaSans, fontWeight = FontWeight(400), fontSize = 15.sp, lineHeight = 22.sp, letterSpacing = 0.005.em),
    label = TextStyle(fontFamily = MonaSans, fontWeight = FontWeight(600), fontSize = 15.sp, lineHeight = 20.sp, letterSpacing = 0.01.em),
    meta = TextStyle(fontFamily = MonaSans, fontWeight = FontWeight(400), fontSize = 13.sp, lineHeight = 18.sp, letterSpacing = 0.01.em),
    timer = TextStyle(fontFamily = MonaSansNarrow, fontWeight = FontWeight(300), fontSize = 22.sp, lineHeight = 26.sp, fontFeatureSettings = "tnum"),
    wordmark = TextStyle(fontFamily = MonaSans, fontWeight = FontWeight(600), fontSize = 17.sp, lineHeight = 22.sp, letterSpacing = (-0.01).em),
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
    val x5 = 56.dp
    val gutter = 20.dp
}

object Radius {
    val chip = 6.dp
    val control = 12.dp
    val sheet = 20.dp
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
    MaterialTheme(colorScheme = scheme) {
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
        val alpha = 0.14f * pressed.value + 0.10f * focused.value
        if (alpha > 0f) drawRect(Color(0xFF808080), alpha = alpha)
    }
}
