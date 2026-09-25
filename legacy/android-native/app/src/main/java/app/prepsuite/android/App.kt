package app.prepsuite.android

import android.app.Application
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import app.prepsuite.android.data.HistoryStore
import app.prepsuite.android.data.Prefs
import app.prepsuite.android.designsystem.PrepTheme
import app.prepsuite.android.navigation.AppRoot
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class PrepSuiteApp : Application() {
    val prefs: Prefs by lazy { Prefs(this) }
    val history: HistoryStore by lazy { HistoryStore(System.currentTimeMillis()) }

    // Outlives screens so a recording can still be finalised after its screen is closed.
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    val audioDir: File get() = File(noBackupFilesDir, "audio").apply { mkdirs() }
}

@Composable
fun prepApp(): PrepSuiteApp = LocalContext.current.applicationContext as PrepSuiteApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        setContent { PrepTheme { AppRoot() } }
    }
}
