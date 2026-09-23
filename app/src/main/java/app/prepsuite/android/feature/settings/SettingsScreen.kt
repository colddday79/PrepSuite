package app.prepsuite.android.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.prepsuite.android.designsystem.ConfirmDialog
import app.prepsuite.android.designsystem.ListRow
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrepToggle
import app.prepsuite.android.designsystem.SectionLabel
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.TopBar
import app.prepsuite.android.prepApp
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val app = prepApp()
    val c = Prep.colors
    val scope = rememberCoroutineScope()
    val quiet by app.prefs.quietMode.collectAsStateWithLifecycle(initialValue = false)
    var storage by remember { mutableLongStateOf(0L) }
    var confirmDelete by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        storage = withContext(Dispatchers.IO) { app.audioDir.listFiles()?.sumOf { it.length() } ?: 0L }
    }

    Column(Modifier.fillMaxSize().background(c.bg).windowInsetsPadding(WindowInsets.safeDrawing)) {
        TopBar(title = "Settings", onBack = onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            SectionLabel("Speaking")
            ListRow(
                title = "Read questions aloud",
                meta = "Turn this off to practise silently. Questions stay on screen.",
                onClick = { scope.launch { app.prefs.setQuietMode(!quiet) } },
                trailing = { PrepToggle(checked = !quiet, onCheckedChange = { on -> scope.launch { app.prefs.setQuietMode(!on) } }) },
            )
            SectionLabel("Your data")
            ListRow(
                title = "Recordings stay on this phone",
                meta = "Saved privately inside the app and never backed up. Uninstalling deletes them.",
                leading = PrepIcons.Lock,
            )
            ListRow(title = "Storage used", value = formatBytes(storage))
            ListRow(title = "Delete all recordings", titleColor = c.danger, leading = PrepIcons.Trash, onClick = { confirmDelete = true })
            SectionLabel("Account")
            ListRow(title = "No account needed", meta = "Optional sign-in with email or Google arrives with feedback.")
            SectionLabel("About")
            ListRow(title = "Version", value = "0.1.0 preview")
            ListRow(title = "Fonts", meta = "Mona Sans and Newsreader · SIL Open Font License 1.1")
            ListRow(title = "Run first-time setup again", onClick = { scope.launch { app.prefs.setOnboarded(false) } })
            Spacer(Modifier.height(Space.x3))
        }
    }

    if (confirmDelete) {
        ConfirmDialog(
            title = "Delete all recordings?",
            body = "This removes every recording and practice session saved on this phone. It can't be undone.",
            confirmLabel = "Delete",
            onConfirm = {
                confirmDelete = false
                scope.launch {
                    withContext(Dispatchers.IO) { app.audioDir.listFiles()?.forEach { it.delete() } }
                    app.history.removeUserSessions()
                    storage = 0L
                }
            },
            onDismiss = { confirmDelete = false },
        )
    }
}

private fun formatBytes(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "${bytes / 1024} KB"
    else -> String.format(Locale.US, "%.1f MB", bytes / 1_048_576.0)
}
