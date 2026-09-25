package app.prepsuite.android.feature.history

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.prepsuite.android.data.HistoryFilter
import app.prepsuite.android.data.HistoryQuery
import app.prepsuite.android.data.HistoryTab
import app.prepsuite.android.data.Pending
import app.prepsuite.android.data.PracticeMode
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.data.SessionSummary
import app.prepsuite.android.designsystem.FilterChip
import app.prepsuite.android.designsystem.GlassCard
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcon
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.QuietButton
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.Tag
import app.prepsuite.android.designsystem.TextInput
import app.prepsuite.android.prepApp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(onStart: () -> Unit, onOpenSession: (SessionSummary) -> Unit = {}) {
    val app = prepApp()
    val c = Prep.colors
    val sessions by app.history.items.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(HistoryTab.All) }
    var role by rememberSaveable { mutableStateOf<RolePack?>(null) }
    var text by rememberSaveable { mutableStateOf("") }
    var showExamples by rememberSaveable { mutableStateOf(true) }
    var roleMenu by remember { mutableStateOf(false) }
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    val selected = sessions.firstOrNull { it.id == selectedId }
    val visibleItems = remember(sessions, showExamples) { if (showExamples) sessions else sessions.filterNot { it.isSample } }
    val filtered = remember(visibleItems, tab, role, text) { HistoryFilter.apply(visibleItems, HistoryQuery(tab, role, text)) }
    val groups = remember(filtered) { HistoryFilter.groupByDay(filtered, LocalDate.now(), ZoneId.systemDefault()) }
    val actualCount = sessions.count { !it.isSample }
    val waitingCount = sessions.count { !it.isSample && it.pending != Pending.None }
    val filtersActive = tab != HistoryTab.All || role != null || text.isNotBlank()

    fun clearFilters() {
        tab = HistoryTab.All
        role = null
        text = ""
    }

    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Column(Modifier.fillMaxWidth().padding(horizontal = Space.gutter).padding(top = Space.xl, bottom = Space.xl)) {
                Text("History", style = Prep.type.titleL, color = c.text)
                Spacer(Modifier.height(Space.s))
                Text("A place for every attempt.", style = Prep.type.bodyL, color = c.text2)
                Spacer(Modifier.height(Space.xl))
                GlassCard {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.xl)) {
                        Column(Modifier.weight(1f)) {
                            Text(actualCount.toString(), style = Prep.type.question, color = c.text)
                            Text(if (actualCount == 1) "Practice record" else "Practice records", style = Prep.type.meta, color = c.text2)
                        }
                        Column(Modifier.weight(1f)) {
                            Text(waitingCount.toString(), style = Prep.type.question, color = c.accent)
                            Text("Ready to revisit", style = Prep.type.meta, color = c.text2)
                        }
                    }
                }
            }
        }
        item {
            TextInput(
                value = text,
                onValueChange = { text = it },
                placeholder = "Search your questions",
                singleLine = true,
                leading = PrepIcons.Search,
                modifier = Modifier.padding(horizontal = Space.gutter)
                    .semantics { contentDescription = "Search practice history" },
            )
        }
        item {
            Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Space.gutter, vertical = Space.m),
                horizontalArrangement = Arrangement.spacedBy(Space.s),
            ) {
                HistoryTab.entries.forEach { option ->
                    FilterChip(option.label, selected = option == tab, onClick = { tab = option })
                }
            }
        }
        item {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = Space.gutter),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Space.s),
            ) {
                Box {
                    FilterChip(role?.short ?: "All roles", selected = role != null, onClick = { roleMenu = true })
                    DropdownMenu(expanded = roleMenu, onDismissRequest = { roleMenu = false }, containerColor = c.surface2) {
                        DropdownMenuItem(text = { Text("All roles", color = c.text) }, onClick = { role = null; roleMenu = false })
                        RolePack.entries.forEach { option ->
                            DropdownMenuItem(text = { Text(option.label, color = c.text) }, onClick = { role = option; roleMenu = false })
                        }
                    }
                }
                FilterChip(if (showExamples) "Samples on" else "Samples off", selected = showExamples, onClick = { showExamples = !showExamples })
            }
        }
        if (showExamples && sessions.any { it.isSample }) {
            item {
                Text(
                    "Sample entries show what's possible. They don't count toward your practice.",
                    style = Prep.type.meta, color = c.text2,
                    modifier = Modifier.padding(horizontal = Space.gutter).padding(top = Space.l),
                )
            }
        }
        if (filtered.isEmpty()) {
            item { EmptyHistory(filtered = filtersActive, onClear = { clearFilters() }, onStart = onStart) }
        } else {
            item {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = Space.gutter).padding(top = Space.xl),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(if (filtered.size == 1) "1 entry" else "${filtered.size} entries", style = Prep.type.meta, color = c.text2)
                    Spacer(Modifier.weight(1f))
                    if (filtersActive) QuietButton("Clear filters", { clearFilters() })
                }
            }
        }
        groups.forEach { (label, entries) ->
            item(key = "day-$label") {
                Text(
                    label, style = Prep.type.label, color = c.text2,
                    modifier = Modifier.padding(horizontal = Space.gutter).padding(top = Space.xl, bottom = Space.s),
                )
            }
            items(entries, key = { it.id }) { item -> HistoryRow(item, onClick = { selectedId = item.id }) }
        }
        item { Spacer(Modifier.height(Space.x3)) }
    }

    if (selected != null) {
        ModalBottomSheet(
            onDismissRequest = { selectedId = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = c.bg,
            contentColor = c.text,
        ) {
            HistoryDetail(
                selected,
                onPractice = { selectedId = null; onOpenSession(selected) },
                onDismiss = { selectedId = null },
            )
        }
    }
}

private fun metaLine(item: SessionSummary): String = when (item.mode) {
    PracticeMode.Quiet -> "Written exercise"
    PracticeMode.Voice -> {
        val attempts = if (item.attempts == 1) "1 attempt" else "${item.attempts} attempts"
        val seconds = item.durationMs / 1000
        if (seconds > 0) "$attempts · %d:%02d".format(seconds / 60, seconds % 60) else attempts
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HistoryRow(item: SessionSummary, onClick: () -> Unit) {
    val c = Prep.colors
    GlassCard(
        Modifier.padding(horizontal = Space.gutter, vertical = Space.xs)
            .clip(RoundedCornerShape(24.dp)).clickable(role = Role.Button, onClick = onClick),
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Space.m)) {
            Box(
                Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)).background(c.surface2),
                contentAlignment = Alignment.Center,
            ) {
                PrepIcon(if (item.mode == PracticeMode.Quiet) PrepIcons.Write else PrepIcons.Mic, null, c.accent, size = 20.dp)
            }
            Column(Modifier.weight(1f)) {
                Text(item.mode.label + " · " + item.role.short, style = Prep.type.meta, color = c.text2)
                Spacer(Modifier.height(Space.s))
                Text(
                    item.questionText,
                    style = Prep.type.bodyL.copy(fontWeight = FontWeight(500)),
                    color = c.text, maxLines = 3, overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(Space.m))
                Text(metaLine(item), style = Prep.type.meta, color = c.text2)
            }
            PrepIcon(PrepIcons.Chevron, null, c.text2, size = 16.dp)
        }
        if (item.pending != Pending.None || item.isSample || item.hasRetry) {
            Spacer(Modifier.height(Space.m))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.s), verticalArrangement = Arrangement.spacedBy(Space.s)) {
                item.pending.label?.let { Tag(it, color = if (item.pending == Pending.RetryWaiting) c.accent else c.pending) }
                if (item.hasRetry && item.pending == Pending.None) Tag("Revisited", color = c.accent)
                if (item.isSample) Tag("Sample", color = c.text2)
            }
        }
    }
}

@Composable
private fun HistoryDetail(item: SessionSummary, onPractice: () -> Unit, onDismiss: () -> Unit) {
    val c = Prep.colors
    val date = Instant.ofEpochMilli(item.createdAt).atZone(ZoneId.systemDefault())
        .format(DateTimeFormatter.ofPattern("d MMM yyyy · h:mm a", Locale.getDefault()))
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Space.gutter),
        verticalArrangement = Arrangement.spacedBy(Space.l),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Practice details", style = Prep.type.titleL, color = c.text, modifier = Modifier.weight(1f))
            if (item.isSample) Tag("Sample", color = c.text2)
        }
        Text(date, style = Prep.type.meta, color = c.text2)
        GlassCard {
            Text("The question", style = Prep.type.meta, color = c.accent)
            Spacer(Modifier.height(Space.m))
            Text(item.questionText, style = Prep.type.questionM, color = c.text)
            Spacer(Modifier.height(Space.l))
            Text(item.role.label + " · " + item.mode.label, style = Prep.type.body, color = c.text2)
            Spacer(Modifier.height(Space.s))
            Text(metaLine(item), style = Prep.type.meta, color = c.text2)
        }
        GlassCard {
            Text(if (item.isSample) "An example of your history" else "Your next step", style = Prep.type.titleM, color = c.text)
            Spacer(Modifier.height(Space.s))
            Text(
                if (item.isSample) "This entry is sample content. Practise the question to make an attempt of your own."
                else when (item.pending) {
                    Pending.RetryWaiting -> "You've set this question aside to try out loud. When you're ready, start a fresh voice attempt."
                    Pending.NotFinished -> "This practice wasn't finished. Start the question again when you have a moment."
                    Pending.None -> "Come back to this question with one thing you'd like to make clearer. Each new attempt is a chance to practise."
                },
                style = Prep.type.bodyL, color = c.text2,
            )
        }
        if (!item.isSample) {
            Text("This entry contains a session summary. A recording or full answer isn't available here.", style = Prep.type.meta, color = c.text2)
        }
        PrimaryButton("Practice this question", onPractice)
        QuietButton("Close details", onDismiss, Modifier.align(Alignment.CenterHorizontally))
        Spacer(Modifier.height(Space.l))
    }
}

@Composable
private fun EmptyHistory(filtered: Boolean, onClear: () -> Unit, onStart: () -> Unit) {
    val c = Prep.colors
    Column(
        Modifier.fillMaxWidth().padding(horizontal = Space.gutter).padding(top = Space.x3),
        verticalArrangement = Arrangement.spacedBy(Space.l),
    ) {
        Box(
            Modifier.size(56.dp).clip(RoundedCornerShape(18.dp)).background(c.accentTint),
            contentAlignment = Alignment.Center,
        ) {
            PrepIcon(if (filtered) PrepIcons.Search else PrepIcons.Clock, null, c.accent)
        }
        Text(if (filtered) "No matching practice." else "Your first attempt belongs here.", style = Prep.type.questionM, color = c.text)
        Text(
            if (filtered) "Try a different question, or clear your filters to see every entry."
            else "Start with one question. Your practice records and questions to revisit will collect here.",
            style = Prep.type.bodyL, color = c.text2,
        )
        if (filtered) QuietButton("Clear filters", onClear) else PrimaryButton("Start practice", onStart)
    }
}
