package app.prepsuite.android.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.animation.*
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.SaveableStateHolder
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.prepsuite.android.data.*
import app.prepsuite.android.designsystem.*
import app.prepsuite.android.feature.feedback.FeedbackScreen
import app.prepsuite.android.feature.feedback.ExampleComparisonScreen
import app.prepsuite.android.feature.history.HistoryScreen
import app.prepsuite.android.feature.onboarding.OnboardingScreen
import app.prepsuite.android.feature.practice.PracticeHomeScreen
import app.prepsuite.android.feature.practice.SessionSetupScreen
import app.prepsuite.android.feature.quiet.QuietPracticeScreen
import app.prepsuite.android.feature.settings.SettingsScreen
import app.prepsuite.android.feature.voice.VoiceSessionScreen
import app.prepsuite.android.feature.pages.*
import app.prepsuite.android.prepApp
import kotlinx.coroutines.launch

sealed interface Route {
    data object Home : Route
    data object Setup : Route
    data object Library : Route
    data class Voice(val questionIds: List<String>, val index: Int, val original: AnswerSnapshot? = null) : Route
    data class Review(val answer: AnswerSnapshot, val original: AnswerSnapshot? = null) : Route
    data class Reflection(val answer: AnswerSnapshot) : Route
    data class Retry(val answer: AnswerSnapshot) : Route
    data class Compare(val original: AnswerSnapshot, val retry: AnswerSnapshot) : Route
    data object FeedbackExample : Route
    data object ComparisonExample : Route
    data object Settings : Route
    data object Account : Route
    data object Profile : Route
    data object SignIn : Route
    data object Privacy : Route
}

enum class HomeTab(val label: String) { Practice("Practice"), Quiet("Quiet practice"), History("History") }

@Composable
fun AppRoot() {
    val app = prepApp()
    val scope = rememberCoroutineScope()
    val onboarded by produceState<Boolean?>(initialValue = null) { app.prefs.onboarded.collect { value = it } }
    Box(Modifier.fillMaxSize().background(Prep.colors.bg)) {
        Crossfade(onboarded, animationSpec = tween(Motion.ENTER), label = "root") { state ->
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
    val tabState = rememberSaveableStateHolder()
    var forward by remember { mutableStateOf(true) }
    var tab by rememberSaveable { mutableStateOf(HomeTab.Practice) }
    val role by app.prefs.role.collectAsStateWithLifecycle(initialValue = RolePack.General)
    val length by app.prefs.sessionLength.collectAsStateWithLifecycle(initialValue = 1)
    val quiet by app.prefs.quietMode.collectAsStateWithLifecycle(initialValue = false)
    fun push(route: Route) { forward = true; backStack.add(route) }
    fun pop() { if (backStack.size > 1) { forward = false; backStack.removeAt(backStack.lastIndex) } }
    fun replaceTop(route: Route) { forward = true; backStack[backStack.lastIndex] = route }
    fun startQuestion(id: String) { push(Route.Voice(listOf(id), 0)) }
    fun finish() { forward = false; backStack.clear(); backStack.add(Route.Home); tab = HomeTab.History }
    fun startSession() { push(Route.Voice(QuestionBank.session(role, length, System.currentTimeMillis()).map { it.id }, 0)) }
    val example = QuestionBank.byId("gen.problem.01")
    BackHandler(backStack.size > 1) { pop() }
    AnimatedContent(
        targetState = backStack.last(),
        transitionSpec = {
            val dir = if (forward) 1 else -1
            (fadeIn(tween(Motion.ENTER)) + slideInHorizontally(tween(Motion.ENTER)) { dir * it / 16 }) togetherWith
                fadeOut(tween(Motion.EXIT))
        }, label = "nav",
    ) { route ->
        when (route) {
            Route.Home -> HomeScreen(
                tab, { tab = it }, role, length, quiet,
                onStart = { startSession() }, onSetup = { push(Route.Setup) },
                onSettings = { push(Route.Settings) }, onLibrary = { push(Route.Library) },
                onProfile = { push(Route.Account) }, onQuestion = { startQuestion(it) }, tabState = tabState,
            )
            Route.Setup -> SessionSetupScreen(role, length,
                onRole = { scope.launch { app.prefs.setRole(it) } },
                onLength = { scope.launch { app.prefs.setSessionLength(it) } },
                onBack = { pop() }, onStart = { pop(); startSession() },
            )
            Route.Library -> LibraryScreen({ pop() }, { startQuestion(it) })
            is Route.Voice -> VoiceSessionScreen(
                questionIds = route.questionIds, index = route.index, role = role,
                onClose = { pop() }, onFeedback = { push(Route.FeedbackExample) },
                onNext = { replaceTop(route.copy(index = route.index + 1)) },
                onTypeInstead = { tab = HomeTab.Quiet; backStack.clear(); backStack.add(Route.Home) },
                onReview = { path, duration ->
                    push(Route.Review(AnswerSnapshot(route.questionIds[route.index], path, duration), route.original))
                },
            )
            is Route.Review -> AnswerReviewScreen(route.answer, { pop() }) { answer ->
                if (route.original == null) push(Route.Reflection(answer))
                else push(Route.Compare(route.original, answer))
            }
            is Route.Reflection -> ReflectionScreen(route.answer, { pop() }, { push(Route.Retry(route.answer)) }, { push(Route.FeedbackExample) }, { finish() })
            is Route.Retry -> RetryPlanScreen(route.answer, { pop() }, { push(Route.Voice(listOf(route.answer.questionId), 0, route.answer)) })
            is Route.Compare -> ComparisonScreen(route.original, route.retry, { pop() }, { push(Route.Retry(route.original)) }, { finish() })
            Route.FeedbackExample -> FeedbackScreen(example, { pop() }, { startQuestion(example.id) }, { push(Route.ComparisonExample) })
            Route.ComparisonExample -> ExampleComparisonScreen({ pop() }, { startQuestion(example.id) })
            Route.Settings -> SettingsScreen({ pop() }, { push(Route.Account) }, { push(Route.Profile) }, { push(Route.Privacy) }, { push(Route.FeedbackExample) })
            Route.Account -> AccountScreen({ pop() }, { push(Route.SignIn) }, { push(Route.Profile) })
            Route.Profile -> ProfileScreen { pop() }
            Route.SignIn -> SignInScreen { pop() }
            Route.Privacy -> PrivacyScreen { pop() }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HomeScreen(
    tab: HomeTab, onTab: (HomeTab) -> Unit, role: RolePack, length: Int, quiet: Boolean,
    onStart: () -> Unit, onSetup: () -> Unit, onSettings: () -> Unit, onLibrary: () -> Unit,
    onProfile: () -> Unit, onQuestion: (String) -> Unit, tabState: SaveableStateHolder,
) {
    val warm by animateFloatAsState(if (tab == HomeTab.Practice) 1f else 0f, tween(Motion.FADE), label = "homeBase")
    AmbientBackground(Modifier.fillMaxSize()) {
        // Practice sits on the warm base lit by the gold presence, edge to edge under the status bar.
        Box(Modifier.matchParentSize().drawBehind { drawRect(HomePalette.bg, alpha = warm) })
        Column(Modifier.align(Alignment.TopCenter).widthIn(max = 760.dp).fillMaxSize()
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal)).imePadding()) {
            Box(Modifier.weight(1f)) {
                Crossfade(tab, animationSpec = tween(Motion.FADE), label = "tab") { t ->
                    tabState.SaveableStateProvider(t.name) {
                        when (t) {
                            HomeTab.Practice -> PracticeHomeScreen(role, length, quiet, onStart, onSetup, onSettings,
                                onWrite = { onTab(HomeTab.Quiet) }, onBrowseQuestions = onLibrary, onProfile = onProfile)
                            HomeTab.Quiet -> QuietPracticeScreen(onVoice = onQuestion)
                            HomeTab.History -> HistoryScreen(onStart = { onTab(HomeTab.Practice) }, onOpenSession = { item ->
                                onQuestion(QuestionBank.all.firstOrNull { it.text == item.questionText }?.id ?: QuestionBank.starter(item.role).id)
                            })
                        }
                    }
                }
            }
            if (!WindowInsets.isImeVisible) BottomTabs(tab, onTab)
        }
    }
}

@Composable
private fun BottomTabs(selected: HomeTab, onSelect: (HomeTab) -> Unit) {
    // Solid and typographic: a hairline, icons and labels, with gold marking the current tab.
    val c = HomePalette
    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
        Hairline(color = c.line)
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Space.s, vertical = Space.xs).selectableGroup(),
            horizontalArrangement = Arrangement.spacedBy(Space.xs),
        ) {
            HomeTab.entries.forEach { tab ->
                val on = tab == selected
                val icon = when (tab) { HomeTab.Practice -> PrepIcons.Home; HomeTab.Quiet -> PrepIcons.Write; HomeTab.History -> PrepIcons.Clock }
                Column(
                    Modifier.weight(1f).heightIn(min = 56.dp).clip(RoundedCornerShape(Radius.control))
                        .selectable(selected = on, role = Role.Tab, onClick = { onSelect(tab) }).padding(vertical = Space.s),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    PrepIcon(icon, null, if (on) c.accent else c.text3, size = 22.dp)
                    Spacer(Modifier.height(Space.xs))
                    Text(tab.label, style = Prep.type.meta.copy(fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium), color = if (on) c.text else c.text3,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
            }
        }
    }
}
