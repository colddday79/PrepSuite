package app.prepsuite.android.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.prepsuite.android.data.QuestionBank
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.designsystem.Hairline
import app.prepsuite.android.designsystem.Motion
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcon
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.feature.feedback.FeedbackScreen
import app.prepsuite.android.feature.history.HistoryScreen
import app.prepsuite.android.feature.onboarding.OnboardingScreen
import app.prepsuite.android.feature.practice.PracticeHomeScreen
import app.prepsuite.android.feature.practice.SessionSetupScreen
import app.prepsuite.android.feature.quiet.QuietPracticeScreen
import app.prepsuite.android.feature.settings.SettingsScreen
import app.prepsuite.android.feature.voice.VoiceSessionScreen
import app.prepsuite.android.prepApp
import kotlinx.coroutines.launch

sealed interface Route {
    data object Home : Route
    data object Setup : Route
    data class Voice(val questionIds: List<String>, val index: Int) : Route
    data class Feedback(val questionId: String) : Route
    data object Settings : Route
}

enum class HomeTab(val label: String) {
    Practice("Practice"),
    Quiet("Quiet practice"),
    History("History"),
}

@Composable
fun AppRoot() {
    val app = prepApp()
    val scope = rememberCoroutineScope()
    val onboarded by produceState<Boolean?>(initialValue = null) { app.prefs.onboarded.collect { value = it } }
    Box(Modifier.fillMaxSize().background(Prep.colors.bg)) {
        Crossfade(targetState = onboarded, animationSpec = tween(Motion.ENTER), label = "root") { state ->
            when (state) {
                null -> Unit
                false -> OnboardingScreen(onDone = { role, notes -> scope.launch { app.prefs.completeOnboarding(role, notes) } })
                true -> MainNav()
            }
        }
    }
}

@Composable
private fun MainNav() {
    val app = prepApp()
    val scope = rememberCoroutineScope()
    val backStack = remember { mutableStateListOf<Route>(Route.Home) }
    var forward by remember { mutableStateOf(true) }
    var tab by rememberSaveable { mutableStateOf(HomeTab.Practice) }
    val role by app.prefs.role.collectAsStateWithLifecycle(initialValue = RolePack.General)
    val length by app.prefs.sessionLength.collectAsStateWithLifecycle(initialValue = 1)
    val quiet by app.prefs.quietMode.collectAsStateWithLifecycle(initialValue = false)

    fun push(route: Route) {
        forward = true
        backStack.add(route)
    }

    fun pop() {
        if (backStack.size > 1) {
            forward = false
            backStack.removeAt(backStack.lastIndex)
        }
    }

    fun replaceTop(route: Route) {
        forward = true
        backStack[backStack.lastIndex] = route
    }

    fun startSession() {
        val ids = QuestionBank.session(role, length, System.currentTimeMillis()).map { it.id }
        push(Route.Voice(ids, 0))
    }

    BackHandler(enabled = backStack.size > 1) { pop() }

    AnimatedContent(
        targetState = backStack.last(),
        transitionSpec = {
            if (targetState is Route.Voice || initialState is Route.Voice) {
                fadeIn(tween(400, easing = Motion.decelerate)) togetherWith fadeOut(tween(250, easing = Motion.accelerate))
            } else {
                val dir = if (forward) 1 else -1
                (fadeIn(tween(Motion.ENTER, easing = Motion.decelerate)) +
                    slideInHorizontally(tween(Motion.ENTER, easing = Motion.decelerate)) { dir * it / 10 }) togetherWith
                    (fadeOut(tween(Motion.EXIT, easing = Motion.accelerate)) +
                        slideOutHorizontally(tween(Motion.EXIT, easing = Motion.accelerate)) { -dir * it / 14 })
            }
        },
        label = "nav",
    ) { route ->
        when (route) {
            Route.Home -> HomeScreen(
                tab = tab,
                onTab = { tab = it },
                role = role,
                length = length,
                quiet = quiet,
                onStart = { startSession() },
                onSetup = { push(Route.Setup) },
                onSettings = { push(Route.Settings) },
            )
            Route.Setup -> SessionSetupScreen(
                role = role,
                length = length,
                onRole = { scope.launch { app.prefs.setRole(it) } },
                onLength = { scope.launch { app.prefs.setSessionLength(it) } },
                onBack = { pop() },
                onStart = {
                    pop()
                    startSession()
                },
            )
            is Route.Voice -> VoiceSessionScreen(
                questionIds = route.questionIds,
                index = route.index,
                role = role,
                onClose = { pop() },
                onFeedback = { push(Route.Feedback(route.questionIds[route.index])) },
                onNext = { replaceTop(route.copy(index = route.index + 1)) },
                onTypeInstead = {
                    tab = HomeTab.Quiet
                    pop()
                },
            )
            is Route.Feedback -> FeedbackScreen(
                question = QuestionBank.byId(route.questionId),
                onBack = { pop() },
                onRetry = { pop() },
            )
            Route.Settings -> SettingsScreen(onBack = { pop() })
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HomeScreen(
    tab: HomeTab,
    onTab: (HomeTab) -> Unit,
    role: RolePack,
    length: Int,
    quiet: Boolean,
    onStart: () -> Unit,
    onSetup: () -> Unit,
    onSettings: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(Prep.colors.bg)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .imePadding(),
    ) {
        Box(Modifier.weight(1f)) {
            Crossfade(targetState = tab, animationSpec = tween(Motion.FADE), label = "tab") { t ->
                when (t) {
                    HomeTab.Practice -> PracticeHomeScreen(
                        role = role,
                        length = length,
                        quiet = quiet,
                        onStart = onStart,
                        onSetup = onSetup,
                        onSettings = onSettings,
                        onWrite = { onTab(HomeTab.Quiet) },
                    )
                    HomeTab.Quiet -> QuietPracticeScreen()
                    HomeTab.History -> HistoryScreen(onStart = { onTab(HomeTab.Practice) })
                }
            }
        }
        if (!WindowInsets.isImeVisible) BottomTabs(tab, onTab)
    }
}

@Composable
private fun BottomTabs(selected: HomeTab, onSelect: (HomeTab) -> Unit) {
    val c = Prep.colors
    Column(Modifier.fillMaxWidth().background(c.bg)) {
        Hairline()
        Row(Modifier.fillMaxWidth().navigationBarsPadding().height(64.dp)) {
            HomeTab.entries.forEach { t ->
                val on = t == selected
                val icon = when (t) {
                    HomeTab.Practice -> PrepIcons.Mic
                    HomeTab.Quiet -> PrepIcons.Write
                    HomeTab.History -> PrepIcons.Clock
                }
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .selectable(selected = on, role = Role.Tab, onClick = { onSelect(t) }),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    PrepIcon(icon, null, if (on) c.text else c.text3, size = 22.dp)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        t.label,
                        style = Prep.type.meta.copy(fontWeight = FontWeight(if (on) 600 else 400)),
                        color = if (on) c.text else c.text3,
                    )
                    Spacer(Modifier.height(6.dp))
                    Box(Modifier.size(width = 18.dp, height = 2.dp).background(if (on) c.text else Color.Transparent))
                }
            }
        }
    }
}
