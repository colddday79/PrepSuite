package app.prepsuite.android.data

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.random.Random
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

enum class RolePack(val label: String, val short: String) {
    General("General first job", "General"),
    CustomerService("Customer service", "Customer service"),
}

enum class Skill(val label: String) {
    Motivation("Motivation"),
    Teamwork("Teamwork"),
    Problem("Handling a problem"),
    Learning("Learning"),
    Customers("Customers"),
}

data class Question(val id: String, val text: String, val skill: Skill, val roles: Set<RolePack>)

object QuestionBank {
    private val shared = setOf(RolePack.General, RolePack.CustomerService)
    private val customer = setOf(RolePack.CustomerService)

    val all = listOf(
        Question("gen.motivation.01", "Why do you want this job?", Skill.Motivation, shared),
        Question("gen.motivation.02", "What do you think this role involves day to day?", Skill.Motivation, shared),
        Question("gen.team.01", "Tell me about a time you worked with other people to get something done.", Skill.Teamwork, shared),
        Question("gen.team.02", "Describe a time you disagreed with someone in a group. What did you do?", Skill.Teamwork, shared),
        Question("gen.problem.01", "Tell me about a time you helped solve a problem.", Skill.Problem, shared),
        Question("gen.problem.02", "Describe a time something didn't go to plan. How did you respond?", Skill.Problem, shared),
        Question("gen.learning.01", "Tell me about something you taught yourself recently.", Skill.Learning, shared),
        Question("gen.learning.02", "Describe a mistake you made and what you learned from it.", Skill.Learning, shared),
        Question("cs.customer.01", "Tell me about a time you helped someone who was frustrated.", Skill.Customers, customer),
        Question("cs.customer.02", "How would you handle a customer asking for something you can't provide?", Skill.Customers, customer),
        Question("cs.customer.03", "Describe a time you went out of your way to help someone.", Skill.Customers, customer),
        Question("cs.pressure.01", "Tell me about a time you stayed calm when things got busy.", Skill.Problem, customer),
    )

    fun byId(id: String): Question = all.first { it.id == id }

    fun forRole(role: RolePack): List<Question> = all.filter { role in it.roles }

    fun starter(role: RolePack): Question =
        byId(if (role == RolePack.CustomerService) "cs.customer.01" else "gen.problem.01")

    fun session(role: RolePack, length: Int, seed: Long): List<Question> {
        val first = starter(role)
        val rest = forRole(role).filter { it.id != first.id }.shuffled(Random(seed))
        return listOf(first) + rest.take((length - 1).coerceAtLeast(0))
    }
}

enum class PracticeMode(val label: String) { Voice("Voice"), Quiet("Quiet") }

enum class Pending(val label: String?) {
    None(null),
    NotFinished("Not finished"),
    RetryWaiting("Retry waiting"),
}

data class SessionSummary(
    val id: String,
    val questionText: String,
    val role: RolePack,
    val mode: PracticeMode,
    val attempts: Int,
    val hasRetry: Boolean,
    val completed: Boolean,
    val pending: Pending,
    val createdAt: Long,
    val isSample: Boolean = false,
    val durationMs: Long = 0,
)

enum class HistoryTab(val label: String) {
    All("All"),
    InProgress("In progress"),
    Retries("Retries"),
    Quiet("Quiet"),
}

data class HistoryQuery(val tab: HistoryTab = HistoryTab.All, val role: RolePack? = null, val text: String = "")

object HistoryFilter {
    fun apply(items: List<SessionSummary>, query: HistoryQuery): List<SessionSummary> {
        val needle = query.text.trim().lowercase(Locale.ROOT)
        return items
            .filter { matchesTab(it, query.tab) }
            .filter { query.role == null || it.role == query.role }
            .filter { needle.isEmpty() || it.questionText.lowercase(Locale.ROOT).contains(needle) }
            .sortedByDescending { it.createdAt }
    }

    private fun matchesTab(item: SessionSummary, tab: HistoryTab): Boolean = when (tab) {
        HistoryTab.All -> true
        HistoryTab.InProgress -> !item.completed || item.pending != Pending.None
        HistoryTab.Retries -> item.hasRetry || item.pending == Pending.RetryWaiting
        HistoryTab.Quiet -> item.mode == PracticeMode.Quiet
    }

    // Expects items already sorted newest first; groupBy keeps that order.
    fun groupByDay(items: List<SessionSummary>, today: LocalDate, zone: ZoneId): List<Pair<String, List<SessionSummary>>> =
        items.groupBy { Instant.ofEpochMilli(it.createdAt).atZone(zone).toLocalDate() }
            .map { (day, list) -> dayLabel(day, today) to list }

    fun dayLabel(day: LocalDate, today: LocalDate): String = when (day) {
        today -> "Today"
        today.minusDays(1) -> "Yesterday"
        else -> day.format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.getDefault()))
    }
}

object SampleHistory {
    private const val HOUR = 3_600_000L
    private const val DAY = 24 * HOUR

    fun build(now: Long): List<SessionSummary> = listOf(
        SessionSummary("sample-1", "Tell me about a time you helped solve a problem.", RolePack.General, PracticeMode.Voice, 2, true, true, Pending.None, now - 2 * HOUR, true, 64_000),
        SessionSummary("sample-2", "Why do you want this job?", RolePack.General, PracticeMode.Voice, 1, false, false, Pending.NotFinished, now - 5 * HOUR, true, 38_000),
        SessionSummary("sample-3", "Tell me about a time you helped someone who was frustrated.", RolePack.CustomerService, PracticeMode.Quiet, 1, false, true, Pending.RetryWaiting, now - DAY, true),
        SessionSummary("sample-4", "Describe a mistake you made and what you learned from it.", RolePack.General, PracticeMode.Voice, 1, false, true, Pending.None, now - 3 * DAY, true, 81_000),
        SessionSummary("sample-5", "How would you handle a customer asking for something you can't provide?", RolePack.CustomerService, PracticeMode.Voice, 3, true, true, Pending.None, now - 5 * DAY, true, 97_000),
        SessionSummary("sample-6", "Tell me about something you taught yourself recently.", RolePack.General, PracticeMode.Quiet, 1, false, true, Pending.None, now - 9 * DAY, true),
    )
}

// In-memory until the Room database lands; seeded with clearly tagged sample sessions.
class HistoryStore(now: Long) {
    private val state = MutableStateFlow(SampleHistory.build(now))
    val items: StateFlow<List<SessionSummary>> = state.asStateFlow()

    fun upsert(item: SessionSummary) = state.update { list -> listOf(item) + list.filterNot { it.id == item.id } }

    fun removeUserSessions() = state.update { list -> list.filter { it.isSample } }
}

enum class ExerciseTemplate(val label: String) {
    Shorten("Shorten it"),
    Contribution("Add your part"),
}

data class Exercise(val template: ExerciseTemplate, val linkedQuestionId: String, val excerpt: String, val instruction: String)

// Deterministic checks for the two starter templates. They never invent facts for the user.
object Exercises {
    val starters = listOf(
        Exercise(
            ExerciseTemplate.Shorten,
            "gen.problem.01",
            "So basically at my school we had this event and there were, like, a lot of problems with it, and we sort of sorted everything out in the end, and it was fine and everyone was happy I think.",
            "Rewrite this in fewer words. Keep the facts that matter.",
        ),
        Exercise(
            ExerciseTemplate.Contribution,
            "gen.problem.01",
            "We sorted everything out in the end.",
            "Rewrite it to say what you personally did. Only use what really happened.",
        ),
    )

    private val fillers = listOf("basically", "like", "sort of", "kind of", "i think", "you know", "just")
    private val keyFacts = listOf("school", "event", "problem")
    private val hedges = setOf("think", "guess", "was", "am", "feel", "mean", "suppose", "don't", "didn't", "wasn't")
    private val resultCues = listOf(" so ", " which ", " because ", " as a result ", " afterwards ", " in the end ", " then ")

    fun check(exercise: Exercise, response: String): String? {
        val text = response.trim()
        if (text.isEmpty()) return null
        return when (exercise.template) {
            ExerciseTemplate.Shorten -> checkShorten(exercise.excerpt, text)
            ExerciseTemplate.Contribution -> checkContribution(text)
        }
    }

    private fun checkShorten(original: String, text: String): String {
        val before = wordCount(original)
        val after = wordCount(text)
        val n = normalise(text)
        val o = normalise(original)
        val lines = mutableListOf<String>()
        lines += if (after < before) {
            "You used $after words instead of $before."
        } else {
            "That's $after words, and the original had $before. Try cutting repeated or filler words."
        }
        val dropped = fillers.filter { o.contains(" $it ") && !n.contains(" $it ") }
        if (dropped.isNotEmpty()) lines += "You dropped filler like ${dropped.take(2).joinToString(" and ") { "“$it”" }}."
        val lost = keyFacts.filter { !n.contains(" $it") }
        lines += if (lost.isEmpty()) "You kept the key facts." else "You left out ${lost.joinToString(", ")}. Keep them if they matter to the answer."
        if (ownAction(n) == null) lines += "It still doesn't say what you personally did. Add that only if it's true."
        return lines.joinToString(" ")
    }

    private fun checkContribution(text: String): String {
        val n = normalise(text)
        val action = ownAction(n)
        val lines = mutableListOf<String>()
        lines += if (action != null) "You named your own action: “I $action…”." else "Try starting with “I” and a verb. What did you do?"
        lines += if (resultCues.any { n.contains(it) }) "You also said what happened because of it." else "If you know what happened next, add it in a few words."
        lines += "If you didn't do anything specific here, that's fine. Choose a different experience instead."
        return lines.joinToString(" ")
    }

    private fun normalise(s: String) = " " + s.lowercase(Locale.ROOT).replace(Regex("[^a-z']+"), " ").trim() + " "

    private fun wordCount(s: String) = s.trim().split(Regex("\\s+")).count { it.isNotBlank() }

    private fun ownAction(normalised: String): String? =
        Regex(" i ([a-z']+)").findAll(normalised).map { it.groupValues[1] }.firstOrNull { it !in hedges }
}
