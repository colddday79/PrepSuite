package app.prepsuite.android.designsystem

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// Hairline icons drawn on a 24-unit grid with one stroke weight, so the set reads as one family.
object PrepIcons {
    val Mic = icon("Mic", "M12 3.5a3 3 0 0 1 3 3v5a3 3 0 0 1 -6 0v-5a3 3 0 0 1 3 -3z M6.5 11.25a5.5 5.5 0 0 0 11 0 M12 16.75v3.75 M9 20.5h6")
    val Write = icon("Write", "M4.5 7h15 M4.5 12h15 M4.5 17h8.5")
    val Clock = icon("Clock", "M12 3.75a8.25 8.25 0 1 1 0 16.5a8.25 8.25 0 1 1 0 -16.5z M12 7.75v4.5l3 1.75")
    val Sliders = icon("Sliders", "M4 7h8.5 M17.5 7h2.5 M15 4.5a2.5 2.5 0 1 1 0 5a2.5 2.5 0 1 1 0 -5z M4 17h2.5 M11.5 17h8.5 M9 14.5a2.5 2.5 0 1 1 0 5a2.5 2.5 0 1 1 0 -5z")
    val Close = icon("Close", "M6.5 6.5l11 11 M17.5 6.5l-11 11")
    val Back = icon("Back", "M14.5 5.5l-6.5 6.5l6.5 6.5")
    val Chevron = icon("Chevron", "M9.5 5.5l6.5 6.5l-6.5 6.5")
    val Play = icon("Play", "M8 5.75v12.5l10 -6.25z")
    val Pause = icon("Pause", "M8.5 6v12 M15.5 6v12")
    val Check = icon("Check", "M5 12.5l4.5 4.5l9.5 -10")
    val Speaker = icon("Speaker", "M4.5 9.5h3l4.5 -4v13l-4.5 -4h-3z M15.5 9a4 4 0 0 1 0 6 M18 6.5a7.5 7.5 0 0 1 0 11")
    val SpeakerOff = icon("SpeakerOff", "M4.5 9.5h3l4.5 -4v13l-4.5 -4h-3z M16 9.5l5 5 M21 9.5l-5 5")
    val Search = icon("Search", "M10.5 4a6.5 6.5 0 1 1 0 13a6.5 6.5 0 1 1 0 -13z M15.5 15.5l4.5 4.5")
    val Replay = icon("Replay", "M4.75 12a7.25 7.25 0 1 0 2.1 -5.1 M4.75 4.5v3.25h3.25")
    val Keyboard = icon("Keyboard", "M3.5 6.5h17v11h-17z M7 10h0.01 M10.5 10h0.01 M14 10h0.01 M17 10h0.01 M8 14h8")
    val Trash = icon("Trash", "M5 7h14 M10 4.5h4 M7 7l0.8 12.5h8.4l0.8 -12.5")
    val Lock = icon("Lock", "M7.5 11v-3a4.5 4.5 0 0 1 9 0v3 M5.5 11h13v9h-13z")
    val Shield = icon("Shield", "M12 3.5l7 3v5c0 4.5 -3 8 -7 9c-4 -1 -7 -4.5 -7 -9v-5z")
    val Home = icon("Home", "M3.5 10.5l8.5 -7l8.5 7 M5.5 9v11h4.5v-6h4v6h4.5v-11")
    val Layers = icon("Layers", "M3 8l9 -5l9 5l-9 5z M3 12l9 5l9 -5 M3 16l9 5l9 -5")
    val ArrowUpRight = icon("ArrowUpRight", "M6 18l12 -12 M6 6h12v12")
    val User = icon("User", "M12 3.5a4 4 0 1 1 0 8a4 4 0 1 1 0 -8z M4.5 20v-1a7.5 5.5 0 0 1 15 0v1")
    val Mail = icon("Mail", "M3.5 5.5h17v13h-17z M3.5 6l8.5 7l8.5 -7")
    val Compass = icon("Compass", "M12 3a9 9 0 1 1 0 18a9 9 0 1 1 0 -18z M15.5 8.5l-2 5l-5 2l2 -5z")
    val Target = icon("Target", "M12 3a9 9 0 1 1 0 18a9 9 0 1 1 0 -18z M12 7a5 5 0 1 1 0 10a5 5 0 1 1 0 -10z M12 11v2")
}

private fun icon(name: String, pathData: String): ImageVector =
    ImageVector.Builder(name = name, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
        .addPath(
            pathData = PathParser().parsePathString(pathData).toNodes(),
            stroke = SolidColor(Color.White),
            strokeLineWidth = 1.5f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        )
        .build()

@Composable
fun PrepIcon(icon: ImageVector, contentDescription: String?, tint: Color, modifier: Modifier = Modifier, size: Dp = 24.dp) {
    Image(
        painter = rememberVectorPainter(icon),
        contentDescription = contentDescription,
        modifier = modifier.size(size),
        colorFilter = ColorFilter.tint(tint),
    )
}
