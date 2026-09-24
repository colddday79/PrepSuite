package app.prepsuite.android.feature.pages

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.designsystem.*
import app.prepsuite.android.prepApp
import kotlinx.coroutines.launch

@Composable
fun AccountScreen(onBack: () -> Unit, onSignIn: () -> Unit, onProfile: () -> Unit) {
    PageLayout("Your space", onBack) {
        PageIntro("PrepSuite", "Preparation,\nat your own pace.", "You can practise without creating an account.")
        GlassPanel {
            Tag("Guest", color = Prep.colors.accent)
            Spacer(Modifier.height(Space.l))
            Text("Make practice personal", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.s))
            Text("Choose your role and keep a few real experiences to draw on.", color = Prep.colors.text2)
            Spacer(Modifier.height(Space.l))
            PrimaryButton("Edit practice profile", onProfile)
        }
        GlassPanel {
            ListRow("Sign in", meta = "Explore email and Google sign-in", leading = PrepIcons.Lock, onClick = onSignIn)
            Hairline()
            ListRow("History stays on this phone", meta = "An account does not currently back up or move your recordings.", leading = PrepIcons.Shield)
        }
    }
}

@Composable
fun SignInScreen(onBack: () -> Unit) {
    var email by rememberSaveable { mutableStateOf("") }
    PageLayout("Sign in", onBack, footer = { QuietButton("Keep practising as a guest", onBack, icon = PrepIcons.Chevron) }) {
        PageIntro("Welcome back", "A space for\nyour next step.", "Practise as a guest for now. Sign-in will be optional.")
        GlassPanel {
            Text("Email address", style = Prep.type.label)
            Spacer(Modifier.height(Space.s))
            TextInput(email, { email = it }, "you@example.com", singleLine = true)
            Spacer(Modifier.height(Space.l))
            PrimaryButton("Continue with email", {}, enabled = false)
            Spacer(Modifier.height(Space.s))
            QuietButton("Continue with Google", {}, enabled = false)
        }
        Notice("Sign-in is not available in this preview. No email is sent and no account is created.")
        Text("Your saved recordings remain on this device. Sign-in will not enable cloud history by itself.", style = Prep.type.body, color = Prep.colors.text2)
    }
}

@Composable
fun ProfileScreen(onBack: () -> Unit) {
    val app = prepApp()
    val scope = rememberCoroutineScope()
    val storedRole by app.prefs.role.collectAsStateWithLifecycle(initialValue = RolePack.General)
    val storedNotes by app.prefs.experienceNotes.collectAsStateWithLifecycle(initialValue = null)
    var notes by rememberSaveable { mutableStateOf<String?>(null) }
    PageLayout("Practice profile", onBack, footer = {
        PrimaryButton("Save profile", { scope.launch { app.prefs.setExperienceNotes(notes ?: storedNotes.orEmpty()); onBack() } })
    }) {
        PageIntro("Your starting point", "You already have\nsomething to talk about.", "School, volunteering, a personal project or helping someone all count as real experience.")
        GlassPanel {
            Text("Preparing for", style = Prep.type.titleM)
            RolePack.entries.forEach { role -> RadioRow(role.label, storedRole == role, { scope.launch { app.prefs.setRole(role) } }) }
        }
        GlassPanel {
            Text("Experience notes", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.s))
            Text("Optional. Keep only details you are comfortable saving on this phone.", color = Prep.colors.text2)
            Spacer(Modifier.height(Space.l))
            TextInput(notes ?: storedNotes.orEmpty(), { notes = it }, "A time you helped, learned, organised or solved something…", minLines = 5)
        }
        GlassPanel { ListRow("Practice language", value = "English", meta = "More languages may be added later.") }
    }
}

@Composable
fun PrivacyScreen(onBack: () -> Unit) {
    PageLayout("Privacy & storage", onBack) {
        PageIntro("You stay in control", "Your words\nare yours.", "Know what is saved and what happens when you leave the app.")
        GlassPanel {
            ListRow("Recordings", meta = "Audio stays in this app’s private storage on your phone. Device backup is disabled for app data.", leading = PrepIcons.Lock)
            Hairline()
            ListRow("Processing", meta = "This preview does not send your recording or notes to a transcription or feedback service.", leading = PrepIcons.Shield)
            Hairline()
            ListRow("History preview", meta = "Session summaries currently last until the app restarts. Rows marked Sample are examples.", leading = PrepIcons.Clock)
        }
        GlassPanel {
            Text("Deleting your data", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.m))
            Text("Use Settings to delete all recordings. Uninstalling the app also removes its local recordings and profile. Deletion cannot be undone.", color = Prep.colors.text2)
        }
        Notice("If remote feedback is added, the app must explain the service and data being sent before you choose to submit.")
    }
}
