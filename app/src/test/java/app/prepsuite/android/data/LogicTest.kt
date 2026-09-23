package app.prepsuite.android.data

import java.time.LocalDate
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoryFilterTest {
    private val day = 86_400_000L
    private val now = LocalDate.of(2026, 9, 23).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli() + 12 * 3_600_000L

    private fun session(
        id: String,
        text: String = "Tell me about a time you helped solve a problem.",
        role: RolePack = RolePack.General,
        mode: PracticeMode = PracticeMode.Voice,
        completed: Boolean = true,
        pending: Pending = Pending.None,
        hasRetry: Boolean = false,
        age: Long = 0,
    ) = SessionSummary(id, text, role, mode, if (hasRetry) 2 else 1, hasRetry, completed, pending, now - age)

    private val items = listOf(
        session("retry", text = "Tell me about a time you helped someone who was frustrated.", role = RolePack.CustomerService, hasRetry = true, age = 2 * day),
        session("done"),
        session("quiet", mode = PracticeMode.Quiet, pending = Pending.RetryWaiting, age = day),
        session("unfinished", completed = false, pending = Pending.NotFinished, age = 1_000),
    )

    private fun ids(query: HistoryQuery) = HistoryFilter.apply(items, query).map { it.id }

    @Test
    fun allIsNewestFirst() = assertEquals(listOf("done", "unfinished", "quiet", "retry"), ids(HistoryQuery()))

    @Test
    fun inProgressIncludesAnyPendingWork() = assertEquals(listOf("unfinished", "quiet"), ids(HistoryQuery(tab = HistoryTab.InProgress)))

    @Test
    fun retriesIncludeWaitingAndCompletedRetries() = assertEquals(listOf("quiet", "retry"), ids(HistoryQuery(tab = HistoryTab.Retries)))

    @Test
    fun quietShowsOnlyWrittenPractice() = assertEquals(listOf("quiet"), ids(HistoryQuery(tab = HistoryTab.Quiet)))

    @Test
    fun roleAndSearchCombineCaseInsensitively() {
        assertEquals(listOf("retry"), ids(HistoryQuery(role = RolePack.CustomerService, text = "  FRUSTRATED ")))
        assertEquals(emptyList<String>(), ids(HistoryQuery(role = RolePack.General, text = "frustrated")))
    }

    @Test
    fun groupsByDayWithRelativeLabels() {
        val groups = HistoryFilter.groupByDay(HistoryFilter.apply(items, HistoryQuery()), LocalDate.of(2026, 9, 23), ZoneOffset.UTC)
        assertEquals(listOf("Today", "Yesterday"), groups.take(2).map { it.first })
        assertEquals(listOf("done", "unfinished"), groups.first().second.map { it.id })
    }
}

class ExercisesTest {
    private val shorten = Exercises.starters.first { it.template == ExerciseTemplate.Shorten }
    private val contribution = Exercises.starters.first { it.template == ExerciseTemplate.Contribution }

    @Test
    fun blankResponseGetsNoExplanation() = assertNull(Exercises.check(shorten, "   "))

    @Test
    fun shorterAnswerThatKeepsFactsIsRecognised() {
        val result = Exercises.check(shorten, "At a school event with problems, I rewrote the rota so it ran on time.")!!
        assertTrue(result, result.startsWith("You used"))
        assertTrue(result, result.contains("You kept the key facts."))
        assertTrue(result, !result.contains("personally did"))
    }

    @Test
    fun contributionAsksForOwnActionWithoutInventingOne() {
        assertTrue(Exercises.check(contribution, "We fixed it.")!!.contains("Try starting with"))
        val named = Exercises.check(contribution, "I called the supplier, so the order arrived in time.")!!
        assertTrue(named, named.contains("I called"))
        assertTrue(named, named.contains("what happened because of it"))
    }

    @Test
    fun hedgesAreNotMistakenForActions() {
        assertTrue(Exercises.check(contribution, "I think it went fine.")!!.contains("Try starting with"))
    }
}
