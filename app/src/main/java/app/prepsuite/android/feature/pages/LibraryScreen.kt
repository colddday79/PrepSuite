package app.prepsuite.android.feature.pages

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import app.prepsuite.android.data.*
import app.prepsuite.android.designsystem.*

@Composable
fun LibraryScreen(onBack: () -> Unit, onQuestion: (String) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var skill by rememberSaveable { mutableStateOf<Skill?>(null) }
    val questions = QuestionBank.all.filter {
        (skill == null || skill == it.skill) && it.text.contains(query.trim(), ignoreCase = true)
    }
    PageLayout("Question library", onBack) {
        PageIntro("Make it yours", "One good question.\nA little more practice.", "Choose a question that fits the experience you want to talk about.")
        TextInput(query, { query = it }, "Search questions", singleLine = true)
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Space.s)) {
            FilterChip("All", skill == null, { skill = null })
            Skill.entries.forEach { item -> FilterChip(item.label, skill == item, { skill = item }) }
        }
        Text("${questions.size} questions", style = Prep.type.meta, color = Prep.colors.text2)
        if (questions.isEmpty()) {
            GlassPanel {
                Text("No questions found", style = Prep.type.titleM)
                Text("Try a different phrase or choose another topic.", color = Prep.colors.text2)
                QuietButton("Clear filters", { query = ""; skill = null })
            }
        }
        questions.forEach { question ->
            GlassCard {
                ListRow(
                    title = question.text,
                    meta = question.skill.label + if (question.roles.size == 1) " · Customer service" else " · Any first job",
                    leading = PrepIcons.Mic,
                    onClick = { onQuestion(question.id) },
                )
            }
        }
    }
}
