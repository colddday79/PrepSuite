package app.prepsuite.android.feature.pages

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.prepsuite.android.designsystem.*

@Composable
fun PageLayout(
    title: String,
    onBack: () -> Unit,
    footer: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    AmbientBackground(Modifier.fillMaxSize()) {
        Column(
            Modifier.align(Alignment.TopCenter).widthIn(max = 760.dp).fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing).imePadding(),
        ) {
            TopBar(title, onBack)
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState())
                    .padding(horizontal = Space.gutter).padding(top = Space.s, bottom = Space.xxl),
                verticalArrangement = Arrangement.spacedBy(Space.l),
                content = content,
            )
            footer?.let { Box(Modifier.padding(horizontal = Space.gutter).padding(top = Space.s, bottom = Space.l)) { it() } }
        }
    }
}

@Composable
fun PageIntro(eyebrow: String, title: String, body: String) {
    Column(verticalArrangement = Arrangement.spacedBy(Space.s), modifier = Modifier.padding(vertical = Space.s)) {
        Text(eyebrow, style = Prep.type.label, color = Prep.colors.accent)
        Text(title, style = Prep.type.question, color = Prep.colors.text)
        Text(body, style = Prep.type.bodyL, color = Prep.colors.text2)
    }
}
