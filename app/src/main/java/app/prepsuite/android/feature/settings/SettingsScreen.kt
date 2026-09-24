package app.prepsuite.android.feature.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.prepsuite.android.designsystem.*
import app.prepsuite.android.feature.pages.PageIntro
import app.prepsuite.android.feature.pages.PageLayout
import app.prepsuite.android.prepApp
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onAccount: () -> Unit = {},
    onProfile: () -> Unit = {},
    onPrivacy: () -> Unit = {},
    onExample: () -> Unit = {},
) {
    val app = prepApp()
    val c = Prep.colors
    val scope = rememberCoroutineScope()
    val quiet by app.prefs.quietMode.collectAsStateWithLifecycle(initialValue = false)
    var storage by remember { mutableLongStateOf(0L) }
    var confirmDelete by remember { mutableStateOf(false) }
    var deletionNotice by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        storage = withContext(Dispatchers.IO) { app.audioDir.listFiles()?.sumOf { it.length() } ?: 0L }
    }
    PageLayout("Settings", onBack) {
        PageIntro("Make yourself comfortable", "Your practice.\nYour preferences.", "A few simple controls for how you practise and what you keep.")
        GlassCard {
            ListRow("Your space", meta = "Account and practice profile", leading = PrepIcons.User, onClick = onAccount)
            Hairline()
            ListRow("Practice profile", meta = "Role, language and experience notes", leading = PrepIcons.Sliders, onClick = onProfile)
        }
        Text("During practice", style = Prep.type.titleM)
        GlassCard {
            ListRow(
                title = "Read questions aloud",
                meta = "Switch off for quiet practice. Questions always stay on screen.",
                trailing = { PrepToggle(checked = !quiet, onCheckedChange = { on -> scope.launch { app.prefs.setQuietMode(!on) } }) },
            )
        }
        Text("Your data", style = Prep.type.titleM)
        GlassCard {
            ListRow("Privacy & storage", meta = "What stays on this phone", leading = PrepIcons.Shield, onClick = onPrivacy)
            Hairline()
            ListRow("Audio storage", value = formatBytes(storage), leading = PrepIcons.Layers)
            Hairline()
            ListRow("Delete all recordings", titleColor = c.danger, leading = PrepIcons.Trash, onClick = { confirmDelete = true })
        }
        deletionNotice?.let { Notice(it) }
        Text("Explore", style = Prep.type.titleM)
        GlassCard {
            ListRow("Example feedback", meta = "See how focused feedback will work", leading = PrepIcons.Target, onClick = onExample)
            Hairline()
            ListRow("First-time introduction", meta = "Revisit the three-step setup", onClick = { scope.launch { app.prefs.setOnboarded(false) } })
            Hairline()
            ListRow("PrepSuite", value = "0.1.0", meta = "Interface preview · Mona Sans, SIL OFL 1.1")
        }
    }
    if (confirmDelete) ConfirmDialog(
        title = "Delete all recordings?",
        body = "This removes recordings and practice summaries from this phone. Your profile is kept. This cannot be undone.",
        confirmLabel = "Delete recordings",
        onConfirm = {
            confirmDelete = false
            scope.launch {
                val failed = withContext(Dispatchers.IO) {
                    app.audioDir.listFiles()?.count { it.exists() && !it.delete() } ?: 0
                }
                if (failed == 0) app.history.removeUserSessions()
                storage = withContext(Dispatchers.IO) { app.audioDir.listFiles()?.sumOf { it.length() } ?: 0L }
                deletionNotice = if (failed == 0) "Your recordings have been deleted." else "Some recordings could not be deleted. Please try again."
            }
        },
        onDismiss = { confirmDelete = false },
    )
}

private fun formatBytes(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "${bytes / 1024} KB"
    else -> String.format(Locale.US, "%.1f MB", bytes / 1_048_576.0)
}
