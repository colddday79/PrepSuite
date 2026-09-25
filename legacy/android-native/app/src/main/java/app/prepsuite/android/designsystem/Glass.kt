package app.prepsuite.android.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp

/** A translucent surface with a restrained light edge; content itself is never blurred. */
@Composable
fun Modifier.glassSurface(shape: Shape = RoundedCornerShape(Radius.card)): Modifier {
    val c = Prep.colors
    return this
        .clip(shape)
        .background(c.glassBg)
        .background(
            Brush.linearGradient(
                colors = listOf(c.cardHighlight, Color.Transparent, c.accent.copy(alpha = 0.025f)),
            )
        )
        .border(
            width = 1.dp,
            brush = Brush.linearGradient(
                colors = listOf(c.glassBorder, c.glassBorder.copy(alpha = 0.055f), c.glassBorder),
            ),
            shape = shape,
        )
}

/** Shared card spacing and treatment for page sections. */
@Composable
fun GlassPanel(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    GlassCard(modifier = modifier, content = content)
}

/** Static light fields provide depth without a continuous animation or a live blur pass. */
@Composable
fun AmbientBackground(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    val c = Prep.colors
    Box(modifier.fillMaxSize().background(c.bg)) {
        Canvas(Modifier.matchParentSize()) {
            drawRect(
                brush = Brush.radialGradient(
                    colors = listOf(c.accent.copy(alpha = 0.105f), Color.Transparent),
                    center = Offset(size.width * 1.05f, size.height * 0.1f),
                    radius = size.width * 0.95f,
                )
            )
            drawRect(
                brush = Brush.radialGradient(
                    colors = listOf(c.voiceWarm.copy(alpha = 0.055f), Color.Transparent),
                    center = Offset(-size.width * 0.22f, size.height * 0.62f),
                    radius = size.width * 0.85f,
                )
            )
        }
        content()
    }
}
