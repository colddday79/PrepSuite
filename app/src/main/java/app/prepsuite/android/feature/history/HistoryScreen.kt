package app.prepsuite.android.feature.history

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.prepsuite.android.data.HistoryFilter
import app.prepsuite.android.data.HistoryQuery
import app.prepsuite.android.data.HistoryTab
import app.prepsuite.android.data.PracticeMode
import app.prepsuite.android.data.RolePack
import app.prepsuite.android.data.SessionSummary
import app.prepsuite.android.designsystem.FilterChip
import app.prepsuite.android.designsystem.Hairline
import app.prepsuite.android.designsystem.Prep
import app.prepsuite.android.designsystem.PrepIcons
import app.prepsuite.android.designsystem.PrimaryButton
import app.prepsuite.android.designsystem.QuietButton
import app.prepsuite.android.designsystem.SectionLabel
import app.prepsuite.android.designsystem.Space
import app.prepsuite.android.designsystem.Tag
import app.prepsuite.android.designsystem.TextInput
import app.prepsuite.android.prepApp
import java.time.LocalDate
import java.time.ZoneId

@Composable
fun HistoryScreen(onStart: () -> Unit) {
    val app = prepApp()
    val c = Prep.colors
    val items by app.history.items.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(HistoryTab.All) }
    var role by rememberSaveable { mutableStateOf<RolePack?>(null) }
    var text by rememberSaveable { mutableStateOf("") }
    val filtered = remember(items, tab, role, text) { HistoryFilter.apply(items, HistoryQuery(tab, role, text)) }
    val groups = remember(filtered) { HistoryFilter.groupByDay(filtered, LocalDate.now(), ZoneId.systemDefault()) }

    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Text(
                "History",
                style = Prep.type.titleL,
                color = c.text,
                modifier = Modifier.padding(horizontal = Space.gutter).padding(top = Space.xl, bottom = Space.l),
            )
        }
        item {
            TextInput(
                value = text,
                onValueChange = { text = it },
                placeholder = "Search questions",
                singleLine = true,
                leading = PrepIcons.Search,
                modifier = Modifier.padding(horizontal = Space.gutter),
            )
        }
        item {
            Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Space.gutter, vertical = Space.s),
                horizontalArrangement = Arrangement.spacedBy(Space.s),
            ) {
                HistoryTab.entries.forEach { t -> FilterChip(t.label, selected = t == tab, onClick = { tab = t }) }
                FilterChip(
                    text = role?.let { "Role: ${it.short}" } ?: "Any role",
                    selected = role != null,
                    onClick = { role = nextRole(role) },
                )
            }
        }
        item {
            Text(
                if (filtered.size == 1) "1 session" else "${filtered.size} sessions",
                style = Prep.type.meta,
                color = c.text3,
                modifier = Modifier.padding(horizontal = Space.gutter, vertical = Space.xs),
            )
        }
        if (filtered.isEmpty()) {
            item {
                EmptyHistory(
                    filtered = items.isNotEmpty(),
                    onClear = {
                        tab = HistoryTab.All
                        role = null
                        text = ""
                    },
                    onStart = onStart,
                )
            }
        }
        groups.forEach { (label, list) ->
            item(key = "day-$label") { SectionLabel(label) }
            items(list, key = { it.id }) { HistoryRow(it) }
        }
        item { Spacer(Modifier.height(Space.xxl)) }
    }
}

private fun nextRole(current: RolePack?): RolePack? = when (current) {
    null -> RolePack.General
    RolePack.General -> RolePack.CustomerService
    RolePack.CustomerService -> null
}

private fun metaLine(item: SessionSummary): String = when (item.mode) {
    PracticeMode.Quiet -> "Quiet · written exercise"
    PracticeMode.Voice -> {
        val attempts = if (item.attempts == 1) "1 attempt" else "${item.attempts} attempts"
        val seconds = item.durationMs / 1000
        if (seconds > 0) "Voice · $attempts · %d:%02d".format(seconds / 60, seconds % 60) else "Voice · $attempts"
    }
}

@Composable
private fun HistoryRow(item: SessionSummary) {
    val c = Prep.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = Space.gutter, vertical = Space.m)) {
        Text(item.questionText, style = Prep.type.bodyL, color = c.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(Space.xs))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.s)) {
            Text(metaLine(item), style = Prep.type.meta, color = c.text3)
            item.pending.label?.let { Tag(it, color = c.pending) }
            if (item.isSample) Tag("Sample", color = c.text3)
        }
    }
    Hairline(Modifier.padding(start = Space.gutter))
}

@Composable
private fun EmptyHistory(filtered: Boolean, onClear: () -> Unit, onStart: () -> Unit) {
    val c = Prep.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = Space.gutter).padding(top = Space.x3)) {
        Text(if (filtered) "Nothing matches these filters." else "No practice yet.", style = Prep.type.titleM, color = c.text)
        Spacer(Modifier.height(Space.s))
        Text(
            if (filtered) "Try a different filter or search." else "Your sessions will appear here after your first answer.",
            style = Prep.type.body,
            color = c.text2,
        )
        Spacer(Modifier.height(Space.l))
        if (filtered) QuietButton("Clear filters", onClear) else PrimaryButton("Start practice", onStart)
    }
}
