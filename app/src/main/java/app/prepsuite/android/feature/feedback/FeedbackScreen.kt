package app.prepsuite.android.feature.feedback

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import app.prepsuite.android.data.Question
import app.prepsuite.android.designsystem.*
import app.prepsuite.android.feature.pages.PageIntro
import app.prepsuite.android.feature.pages.PageLayout

@Composable
fun FeedbackScreen(question: Question, onBack: () -> Unit, onRetry: () -> Unit, onCompare: () -> Unit = {}) {
    var reported by remember { mutableStateOf(false) }
    PageLayout("Example feedback", onBack, footer = { PrimaryButton("Practise this question", onRetry) }) {
        PageIntro("A closer look", "One thing to keep.\nOne thing to try.", "This fictional example shows the feedback layout. It is not based on your recording.")
        GlassPanel {
            Tag("Example question", color = Prep.colors.pending)
            Spacer(Modifier.height(Space.m))
            Text(question.text, style = Prep.type.questionM)
        }
        GlassPanel {
            Row(horizontalArrangement = Arrangement.spacedBy(Space.s)) {
                PrepIcon(PrepIcons.Check, null, Prep.colors.accent)
                Text("What worked", style = Prep.type.titleM)
            }
            Spacer(Modifier.height(Space.m))
            Text("The example answer describes a specific school event and a problem the group faced.", style = Prep.type.bodyL)
        }
        GlassPanel {
            Tag("Personal contribution")
            Spacer(Modifier.height(Space.m))
            Text("Name your own action", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.m))
            QuoteBlock("We sorted everything out.")
            Spacer(Modifier.height(Space.s))
            Text("Illustrative quote · No sample audio", style = Prep.type.meta, color = Prep.colors.text2)
            Spacer(Modifier.height(Space.l))
            Hairline()
            Spacer(Modifier.height(Space.l))
            Text("Why it matters", style = Prep.type.label)
            Spacer(Modifier.height(Space.s))
            Text("The listener can understand the group’s result, but not what this person contributed.", color = Prep.colors.text2)
            Spacer(Modifier.height(Space.l))
            Text("One thing to try", style = Prep.type.label)
            Spacer(Modifier.height(Space.s))
            Text("Say one action you took yourself and what happened next. If you cannot remember, choose another experience.", color = Prep.colors.text2)
        }
        QuietButton("See example comparison", onCompare, icon = PrepIcons.Layers)
        QuietButton(if (reported) "Report noted for this preview" else "This feedback seems wrong", { reported = true }, enabled = !reported)
    }
}

@Composable
fun ExampleComparisonScreen(onBack: () -> Unit, onPractice: () -> Unit) {
    PageLayout("Example comparison", onBack, footer = { PrimaryButton("Try it with your own answer", onPractice) }) {
        PageIntro("Illustrative example", "A more specific\ncontribution.", "These fictional excerpts demonstrate the comparison layout. There is no sample recording.")
        GlassPanel {
            Tag("Original", color = Prep.colors.text2)
            Spacer(Modifier.height(Space.m))
            QuoteBlock("We sorted everything out.")
        }
        GlassPanel {
            Tag("Retry", color = Prep.colors.accent)
            Spacer(Modifier.height(Space.m))
            QuoteBlock("I wrote down the tasks and asked each volunteer to choose one. That helped us get the stall ready on time.")
        }
        GlassPanel {
            Text("What changed", style = Prep.type.titleM)
            Spacer(Modifier.height(Space.s))
            Text("The retry names a personal action and a result. In your own answer, include these details only if they are true.", color = Prep.colors.text2)
        }
    }
}
