import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/assistant.dart';
import 'package:prepsuite/design/assistant_avatar.dart';
import 'package:prepsuite/design/components.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/design/tokens.dart';
import 'package:prepsuite/features/drills/drill_content.dart';
import 'package:prepsuite/features/drills/drill_lesson_screen.dart';
import 'package:prepsuite/features/drills/drill_progress.dart';
import 'package:prepsuite/features/drills/skill_path.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------------------------
// Content

Iterable<DrillLesson> get _lessons => drillCurriculum.expand((s) => s.lessons);
Iterable<DrillExercise> get _exercises => _lessons.expand((l) => l.exercises);

/// Every string a person can read in the curriculum.
Iterable<String> get _allText sync* {
  for (final skill in drillCurriculum) {
    yield skill.title;
    yield skill.summary;
    for (final lesson in skill.lessons) {
      yield lesson.title;
      yield lesson.takeaway;
      for (final e in lesson.exercises) {
        yield e.instruction;
        yield e.prompt;
        if (e.asked != null) yield e.asked!;
        switch (e) {
          case ChoiceExercise():
            yield* e.options;
            yield e.why;
          case OddOneOutExercise():
            yield* e.sentences;
            yield e.why;
          case FillBlankExercise():
            yield e.before;
            yield e.after;
            yield* e.bank;
            yield e.why;
          case OrderExercise():
            yield* e.steps;
            yield* e.labels ?? const [];
            yield e.why;
          case RewriteExercise():
            yield e.line;
            yield e.model;
            yield e.tip;
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------------------------
// Widget harness

bool _fontLoaded = false;

Future<void> _boot(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(411, 891),
  double textScale = 1,
}) async {
  HologramVideo.instance.enabled = false;
  AssistantAvatar.live = false;
  if (!_fontLoaded) {
    // Real Mona Sans metrics, so overflow checks match the device.
    await tester.runAsync(() async {
      final loader = FontLoader('MonaSans')..addFont(rootBundle.load('assets/fonts/MonaSans.ttf'));
      await loader.load();
    });
    _fontLoaded = true;
  }
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: prepTheme(),
      debugShowCheckedModeBanner: false,
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: page!,
      ),
      home: home,
    ),
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester, [int ms = 500]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

/// A plain page with a button that opens [lesson], so closing the lesson has somewhere to go.
Widget _launcher(
  DrillProgressStore progress, {
  DrillSkill? skill,
  DrillLesson? lesson,
  VoidCallback? onPracticeAloud,
}) {
  final s = skill ?? drillCurriculum.first;
  final l = lesson ?? s.lessons.first;
  return Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          key: const ValueKey('open-lesson'),
          onPressed: () => openDrillLesson(
            context,
            skill: s,
            lesson: l,
            look: AssistantLook.nova,
            progress: progress,
            onPracticeAloud: onPracticeAloud,
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

/// The exercise on screen, read from its key.
DrillExercise _current(WidgetTester tester) {
  final keyed = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith('drill-exercise-');
  });
  expect(keyed, findsOneWidget);
  final id = (tester.widget(keyed).key! as ValueKey<String>).value.substring('drill-exercise-'.length);
  return _exercises.firstWhere((e) => e.id == id);
}

/// Answers [e] right or wrong, then taps Check.
Future<void> _answer(WidgetTester tester, DrillExercise e, {required bool right}) async {
  switch (e) {
    case ChoiceExercise():
      final i = right ? e.answer : (e.answer + 1) % e.options.length;
      await _tap(tester, find.byKey(ValueKey('drill-option-$i')));
    case OddOneOutExercise():
      final i = right ? e.answer : (e.answer + 1) % e.sentences.length;
      await _tap(tester, find.byKey(ValueKey('drill-option-$i')));
    case FillBlankExercise():
      final i = right ? e.answerIndex : (e.answerIndex + 1) % e.bank.length;
      await _tap(tester, find.byKey(ValueKey('drill-tile-$i')));
    case OrderExercise():
      final steps = List.generate(e.steps.length, (i) => i);
      for (final step in right ? steps : steps.reversed) {
        await _tap(tester, find.byKey(ValueKey('drill-tile-$step')));
      }
    case RewriteExercise():
      await tester.enterText(
        find.byKey(const ValueKey('drill-rewrite-field')),
        'I ran the sign-up table for our food drive last fall.',
      );
      await _settle(tester, 100);
  }
  await _tap(tester, find.byKey(const ValueKey('drill-check')));
}

/// Taps something that closes a route, and waits out the page transition.
Future<void> _leave(WidgetTester tester, Finder finder) async {
  await _tap(tester, finder);
  await _settle(tester, 1000);
}

Future<void> _continue(WidgetTester tester) => _tap(tester, find.byKey(const ValueKey('drill-continue')));

/// The lesson's close control, whatever it is drawn as: found by what screen readers hear.
Finder _closeLesson() => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Close lesson');

PrimaryButton _checkButton(WidgetTester tester) => tester.widget<PrimaryButton>(find.byKey(const ValueKey('drill-check')));

// ---------------------------------------------------------------------------------------------

void main() {
  setUp(() => PrepColors.useAccent(AssistantLook.nova.tone));

  group('curriculum', () {
    test('four skills in path order, two lessons each, five or six exercises per lesson', () {
      expect(drillCurriculum.map((s) => s.title), [
        'Introducing yourself',
        'Explaining an example',
        'Answering a follow-up',
        'Clear delivery',
      ]);
      for (final skill in drillCurriculum) {
        expect(skill.lessons, hasLength(2), reason: skill.id);
        expect(skill.summary, isNotEmpty);
        for (final lesson in skill.lessons) {
          expect(lesson.exercises.length, inInclusiveRange(5, 6), reason: lesson.id);
          expect(lesson.takeaway, isNotEmpty);
          expect(lesson.scoredCount, greaterThan(0));
        }
      }
    });

    test('every id is unique', () {
      final ids = [
        ...drillCurriculum.map((s) => s.id),
        ..._lessons.map((l) => l.id),
        ..._exercises.map((e) => e.id),
      ];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.every((id) => id.isNotEmpty), isTrue);
    });

    test('each exercise has exactly one valid answer', () {
      for (final e in _exercises) {
        switch (e) {
          case ChoiceExercise():
            expect(e.options.length, inInclusiveRange(3, 4), reason: e.id);
            expect(e.answer, inInclusiveRange(0, e.options.length - 1), reason: e.id);
            expect(e.options.toSet(), hasLength(e.options.length), reason: e.id);
            expect(e.why, isNotEmpty);
          case OddOneOutExercise():
            expect(e.sentences.length, inInclusiveRange(3, 4), reason: e.id);
            expect(e.answer, inInclusiveRange(0, e.sentences.length - 1), reason: e.id);
            expect(e.sentences.toSet(), hasLength(e.sentences.length), reason: e.id);
            expect(e.why, isNotEmpty);
          case FillBlankExercise():
            expect(e.bank.length, inInclusiveRange(3, 4), reason: e.id);
            expect(e.bank.where((w) => w == e.answer), hasLength(1), reason: e.id);
            expect(e.bank.toSet(), hasLength(e.bank.length), reason: e.id);
            expect(e.why, isNotEmpty);
          case OrderExercise():
            expect(e.steps.length, inInclusiveRange(3, 4), reason: e.id);
            expect([...e.start]..sort(), List.generate(e.steps.length, (i) => i), reason: '${e.id} start');
            expect(e.start, isNot(List.generate(e.steps.length, (i) => i)), reason: '${e.id} starts solved');
            if (e.labels != null) expect(e.labels, hasLength(e.steps.length), reason: e.id);
            expect(e.why, isNotEmpty);
          case RewriteExercise():
            expect(drillWordCount(e.model), greaterThanOrEqualTo(RewriteExercise.minWords), reason: e.id);
            expect(e.tip, isNotEmpty);
        }
      }
    });

    test('at most one rewrite per lesson, and only in the last position', () {
      for (final lesson in _lessons) {
        final rewrites = [
          for (final (i, e) in lesson.exercises.indexed)
            if (e is RewriteExercise) i,
        ];
        expect(rewrites.length, lessThanOrEqualTo(1), reason: lesson.id);
        if (rewrites.isNotEmpty) expect(rewrites.single, lesson.exercises.length - 1, reason: lesson.id);
      }
    });

    test('right answers are spread across positions, not always in the same slot', () {
      final positions = <int>{
        for (final e in _exercises)
          if (e is ChoiceExercise) e.answer,
      };
      expect(positions, containsAll([0, 1, 2, 3]));
    });

    test('the copy has no em dashes, emoji or other non-ASCII characters', () {
      for (final text in _allText) {
        expect(text, isNot(contains('—')), reason: text);
        expect(text, isNot(contains('–')), reason: text);
        expect(text.runes.every((r) => r < 128), isTrue, reason: text);
      }
    });

    test('lookups find a lesson and its skill', () {
      expect(drillLessonById('followup-2')?.title, 'Add the missing detail');
      expect(drillSkillFor('followup-2')?.id, 'followup');
      expect(drillLessonById('nope'), isNull);
      expect(drillSkillFor('nope'), isNull);
    });

    test('word count and the gentle rewrite tip', () {
      expect(drillWordCount('  one two   three '), 3);
      expect(drillWordCount(''), 0);
      final rewrite = drillLessonById('example-1')!.exercises.last as RewriteExercise;
      expect(rewriteTip(rewrite, 'The team made a schedule for everyone.'), 'Try saying what you did, with "I".');
      expect(rewriteTip(rewrite, 'I basically made the schedule for everyone.'), 'Try it once more without "basically".');
      expect(rewriteTip(rewrite, 'Um I made the schedule for everyone.'), 'Try it once more without "um".');
      expect(rewriteTip(rewrite, 'I made the schedule for 12 volunteers.'), rewrite.tip);
      // "like" as a real verb is not a filler.
      expect(rewriteTip(rewrite, 'I like making schedules for 12 volunteers.'), rewrite.tip);
    });
  });

  group('progress store', () {
    test('complete, done counts and the next lesson', () async {
      final store = DrillProgressStore();
      final intro = drillCurriculum.first;
      expect(store.restored, isTrue);
      expect(store.nextLesson()?.id, 'intro-1');
      expect(store.doneCount(intro), 0);

      var notified = 0;
      store.addListener(() => notified++);
      await store.complete('intro-1', 4, 5);
      expect(notified, 1);
      expect(store.isDone('intro-1'), isTrue);
      expect(store.doneCount(intro), 1);
      expect(store.nextLesson()?.id, 'intro-2');
      expect(store.skillOf(store.nextLesson()!).id, 'intro');

      // Out of order is fine; next is still the first unfinished lesson in path order.
      await store.complete('delivery-1', 6, 6);
      expect(store.nextLesson()?.id, 'intro-2');
      expect(store.doneTotal, 2);
    });

    test('keeps the best score', () async {
      final store = DrillProgressStore();
      await store.complete('intro-1', 4, 5);
      await store.complete('intro-1', 2, 5);
      expect(store.best('intro-1')?.correct, 4);
      await store.complete('intro-1', 5, 5);
      expect(store.best('intro-1')?.correct, 5);
    });

    test('nextLesson is null once every lesson is done', () async {
      final store = DrillProgressStore();
      for (final lesson in _lessons) {
        await store.complete(lesson.id, lesson.scoredCount, lesson.scoredCount);
      }
      expect(store.nextLesson(), isNull);
      expect(store.allDone, isTrue);
      expect(store.doneTotal, store.lessonCount);
      expect(store.lessonCount, 8);
    });

    test('persists across launches', () async {
      SharedPreferences.setMockInitialValues({});
      final first = DrillProgressStore(persist: true);
      await first.restore();
      await first.complete('intro-1', 3, 5);
      await first.complete('example-2', 5, 5);

      final saved = (await SharedPreferences.getInstance()).getString(DrillProgressStore.storageKey);
      expect(jsonDecode(saved!), {
        'lessons': {
          'intro-1': {'correct': 3, 'total': 5},
          'example-2': {'correct': 5, 'total': 5},
        },
      });

      final second = DrillProgressStore(persist: true);
      expect(second.restored, isFalse);
      expect(second.isDone('intro-1'), isFalse);
      await second.restore();
      expect(second.restored, isTrue);
      expect(second.isDone('intro-1'), isTrue);
      expect(second.best('intro-1')?.correct, 3);
      expect(second.isDone('example-2'), isTrue);
      expect(second.nextLesson()?.id, 'intro-2');

      await second.clear();
      final third = DrillProgressStore(persist: true);
      await third.restore();
      expect(third.doneTotal, 0);
    });

    test('a lesson finished while loading keeps its better score', () async {
      SharedPreferences.setMockInitialValues({
        DrillProgressStore.storageKey: jsonEncode({
          'lessons': {
            'intro-1': {'correct': 2, 'total': 5},
          },
        }),
      });
      final store = DrillProgressStore(persist: true);
      await store.complete('intro-1', 5, 5);
      await store.restore();
      expect(store.best('intro-1')?.correct, 5);
    });

    test('unreadable preferences start empty', () async {
      for (final bad in <Object>[
        'not json',
        '[1, 2]',
        '{"lessons": 3}',
        42,
      ]) {
        SharedPreferences.setMockInitialValues({DrillProgressStore.storageKey: bad});
        final store = DrillProgressStore(persist: true);
        await store.restore();
        expect(store.restored, isTrue, reason: '$bad');
        expect(store.doneTotal, 0, reason: '$bad');
      }
    });

    test('malformed entries are skipped, good ones kept', () async {
      SharedPreferences.setMockInitialValues({
        DrillProgressStore.storageKey: jsonEncode({
          'lessons': {
            'intro-1': {'correct': 4, 'total': 5},
            'intro-2': {'correct': 'four', 'total': 5},
            'example-1': {'correct': 9, 'total': 5},
            'example-2': 'done',
          },
        }),
      });
      final store = DrillProgressStore(persist: true);
      await store.restore();
      expect(store.isDone('intro-1'), isTrue);
      expect(store.isDone('intro-2'), isFalse);
      expect(store.isDone('example-1'), isFalse);
      expect(store.isDone('example-2'), isFalse);
    });

    test('the shared instance saves on this phone', () {
      expect(DrillProgressStore.instance.persist, isTrue);
      expect(identical(DrillProgressStore.instance, DrillProgressStore.instance), isTrue);
    });
  });

  group('lesson', () {
    testWidgets('a miss comes back at the end, then the lesson completes and is saved', (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final progress = DrillProgressStore();
      final lesson = drillCurriculum.first.lessons.first;
      await _boot(tester, _launcher(progress));
      await _tap(tester, find.byKey(const ValueKey('open-lesson')));
      expect(find.byType(DrillLessonScreen), findsOneWidget);
      expect(find.text('Introducing yourself'), findsOneWidget);
      expect(_checkButton(tester).onPressed, isNull, reason: 'Check waits for an answer');

      // First exercise: wrong.
      final first = _current(tester);
      expect(first.id, lesson.exercises.first.id);
      await _answer(tester, first, right: false);
      expect(find.text('Not quite.'), findsOneWidget);
      expect(find.text('Your pick'), findsOneWidget);
      expect(find.text('Best answer'), findsOneWidget);
      expect(find.text('Comes back at the end'), findsOneWidget);
      expect(haptics, isEmpty);
      await _continue(tester);

      // The rest: right.
      final seen = <String>[first.id];
      for (var i = 1; i < lesson.exercises.length; i++) {
        final e = _current(tester);
        seen.add(e.id);
        await _answer(tester, e, right: true);
        if (e is RewriteExercise) {
          expect(find.text('Compare yours'), findsOneWidget);
          expect(find.text(e.model), findsOneWidget);
        } else {
          expect(find.text('Nice.'), findsOneWidget);
        }
        await _continue(tester);
      }
      expect(seen, lesson.exercises.map((e) => e.id));
      expect(haptics, everyElement('HapticFeedbackType.selectionClick'));
      expect(haptics, hasLength(lesson.scoredCount - 1));

      // The missed one is back, marked as a second try.
      expect(_current(tester).id, first.id);
      expect(find.textContaining('Second try'), findsOneWidget);
      await _answer(tester, first, right: true);
      expect(find.text('Nice.'), findsOneWidget);
      expect(progress.isDone(lesson.id), isFalse, reason: 'saved only when the lesson completes');
      await _continue(tester);

      expect(find.text('Lesson complete'), findsOneWidget);
      expect(find.text('${lesson.scoredCount - 1}/${lesson.scoredCount}'), findsOneWidget);
      expect(find.text('right first time'), findsOneWidget);
      expect(find.textContaining('one you missed'), findsOneWidget);
      expect(find.text(lesson.takeaway), findsOneWidget);
      expect(progress.isDone(lesson.id), isTrue);
      expect(progress.best(lesson.id)?.correct, lesson.scoredCount - 1);
      expect(progress.best(lesson.id)?.total, lesson.scoredCount);
      // No callback, no spoken practice offer.
      expect(find.byKey(const ValueKey('drill-aloud')), findsNothing);

      await _leave(tester, find.byKey(const ValueKey('drill-done')));
      expect(find.byType(DrillLessonScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('all right first time, then Practice it out loud closes and calls back', (tester) async {
      final progress = DrillProgressStore();
      final skill = drillCurriculum[3];
      final lesson = skill.lessons[1];
      var aloud = 0;
      await _boot(tester, _launcher(progress, skill: skill, lesson: lesson, onPracticeAloud: () => aloud++));
      await _tap(tester, find.byKey(const ValueKey('open-lesson')));
      for (var i = 0; i < lesson.exercises.length; i++) {
        await _answer(tester, _current(tester), right: true);
        await _continue(tester);
      }
      expect(find.text('${lesson.scoredCount}/${lesson.scoredCount}'), findsOneWidget);
      expect(find.text('right first time'), findsOneWidget);
      await _leave(tester, find.byKey(const ValueKey('drill-aloud')));
      expect(aloud, 1);
      expect(find.byType(DrillLessonScreen), findsNothing);
      expect(progress.best(lesson.id)?.correct, lesson.scoredCount);
    });

    testWidgets('closing mid-lesson asks first and saves nothing', (tester) async {
      final progress = DrillProgressStore();
      await _boot(tester, _launcher(progress));
      await _tap(tester, find.byKey(const ValueKey('open-lesson')));

      // Nothing answered yet: close leaves straight away.
      await _leave(tester, _closeLesson());
      expect(find.byType(DrillLessonScreen), findsNothing);

      await _tap(tester, find.byKey(const ValueKey('open-lesson')));
      await _tap(tester, find.byKey(const ValueKey('drill-option-0')));
      await _tap(tester, _closeLesson());
      expect(find.text('Leave this lesson?'), findsOneWidget);
      await _tap(tester, find.text('Keep going'));
      expect(find.byType(DrillLessonScreen), findsOneWidget);

      await _tap(tester, _closeLesson());
      await _leave(tester, find.text('Leave'));
      expect(find.byType(DrillLessonScreen), findsNothing);
      expect(progress.doneTotal, 0);
    });

    testWidgets('ordering fills top to bottom, and a placed part can be taken back', (tester) async {
      final skill = drillCurriculum[1];
      final lesson = skill.lessons[1];
      final order = lesson.exercises.first as OrderExercise;
      await _boot(
        tester,
        DrillLessonScreen(lesson: lesson, skill: skill, look: AssistantLook.iris, progress: DrillProgressStore()),
      );
      await _tap(tester, find.byKey(const ValueKey('drill-tile-2')));
      await _tap(tester, find.byKey(const ValueKey('drill-tile-0')));
      // Step 1 holds part 2, step 2 holds part 0; the bank no longer shows them.
      expect(find.descendant(of: find.byKey(const ValueKey('drill-slot-0')), matching: find.text(order.steps[2])), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('drill-slot-1')), matching: find.text(order.steps[0])), findsOneWidget);
      expect(find.byKey(const ValueKey('drill-tile-2')), findsNothing);

      // Take step 1 back: the slot empties and the part returns to the bank.
      await _tap(tester, find.byKey(const ValueKey('drill-slot-0')));
      expect(find.descendant(of: find.byKey(const ValueKey('drill-slot-0')), matching: find.text(order.steps[2])), findsNothing);
      expect(find.byKey(const ValueKey('drill-tile-2')), findsOneWidget);

      // The next part fills the first empty step.
      await _tap(tester, find.byKey(const ValueKey('drill-tile-3')));
      expect(find.descendant(of: find.byKey(const ValueKey('drill-slot-0')), matching: find.text(order.steps[3])), findsOneWidget);
      expect(_checkButton(tester).onPressed, isNull);
    });

    testWidgets('fill in the blank: a tile goes into the gap and can be swapped', (tester) async {
      final skill = drillCurriculum.first;
      final lesson = skill.lessons.first;
      final fill = lesson.exercises.whereType<FillBlankExercise>().first;
      await _boot(tester, DrillLessonScreen(lesson: lesson, skill: skill, look: AssistantLook.nova, progress: DrillProgressStore()));
      // Get to the fill-in exercise.
      while (_current(tester).id != fill.id) {
        await _answer(tester, _current(tester), right: true);
        await _continue(tester);
      }
      final gap = find.byKey(const ValueKey('drill-gap'));
      await _tap(tester, find.byKey(const ValueKey('drill-tile-0')));
      expect(find.descendant(of: gap, matching: find.text(fill.bank[0])), findsOneWidget);
      await _tap(tester, find.byKey(ValueKey('drill-tile-${fill.answerIndex}')));
      expect(find.descendant(of: gap, matching: find.text(fill.answer)), findsOneWidget);
      // Tapping the word in the gap takes it out again.
      await _tap(tester, find.descendant(of: gap, matching: find.text(fill.answer)));
      expect(find.descendant(of: gap, matching: find.text(fill.answer)), findsNothing);
      expect(_checkButton(tester).onPressed, isNull);
    });

    testWidgets('the rewrite needs six words and is writing practice, not speaking', (tester) async {
      final skill = drillCurriculum.first;
      final lesson = skill.lessons.first;
      await _boot(tester, DrillLessonScreen(lesson: lesson, skill: skill, look: AssistantLook.nova, progress: DrillProgressStore()));
      while (_current(tester) is! RewriteExercise) {
        await _answer(tester, _current(tester), right: true);
        await _continue(tester);
      }
      expect(find.text('Writing practice, not speaking'), findsOneWidget);
      final field = find.byKey(const ValueKey('drill-rewrite-field'));
      await tester.enterText(field, 'We did a lot of');
      await tester.pump();
      expect(_checkButton(tester).onPressed, isNull);
      expect(find.text('At least 6 words (5 so far)'), findsOneWidget);
      await tester.enterText(field, 'We did a lot of things.');
      await tester.pump();
      expect(_checkButton(tester).onPressed, isNotNull);
      await _tap(tester, find.byKey(const ValueKey('drill-check')));
      // No right or wrong: a model to compare and a gentle tip.
      expect(find.text('Compare yours'), findsOneWidget);
      expect(find.text('Not quite.'), findsNothing);
      expect(find.text('Try saying what you did, with "I".'), findsOneWidget);
    });
  });

  group('skill path', () {
    testWidgets('shows four skills, marks the next lesson and opens any lesson', (tester) async {
      final progress = DrillProgressStore();
      await progress.complete('intro-1', 5, 5);
      final opened = <String>[];
      await _boot(
        tester,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(Space.gutter),
            children: [
              SkillPath(progress: progress, onOpenLesson: (skill, lesson) => opened.add('${skill.id}/${lesson.id}')),
            ],
          ),
        ),
      );
      for (final skill in drillCurriculum) {
        expect(find.text(skill.title), findsOneWidget);
      }
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('0/2'), findsNWidgets(3));
      // "Up next" sits on the first unfinished lesson only.
      final upNext = find.descendant(of: find.byKey(const ValueKey('skill-lesson-intro-2')), matching: find.textContaining('Up next'));
      expect(upNext, findsOneWidget);
      expect(find.textContaining('Up next'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('skill-lesson-followup-2')));
      expect(opened, ['followup/followup-2']);

      // Finishing a lesson moves "Up next" along.
      await progress.complete('intro-2', 4, 5);
      await tester.pump();
      expect(
        find.descendant(of: find.byKey(const ValueKey('skill-lesson-example-1')), matching: find.textContaining('Up next')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Home card names the next lesson, then offers practice again', (tester) async {
      final progress = DrillProgressStore();
      final opened = <String>[];
      await _boot(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(Space.gutter),
            child: NextLessonCard(progress: progress, onOpen: (skill, lesson) => opened.add(lesson.id)),
          ),
        ),
      );
      expect(find.text('Your opening'), findsOneWidget);
      expect(find.text('Introducing yourself'), findsOneWidget);
      expect(find.text('0/8'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('next-lesson-card')));
      expect(opened, ['intro-1']);

      for (final lesson in _lessons) {
        await progress.complete(lesson.id, 1, 1);
      }
      await tester.pump();
      expect(find.text('All lessons done'), findsOneWidget);
      expect(find.text('Start again'), findsOneWidget);
      expect(find.text('8/8'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('next-lesson-card')));
      expect(opened, ['intro-1', 'intro-1']);
    });
  });

  group('layout', () {
    for (final (name, size, scale) in [
      ('small phone at 1.3x text', const Size(360, 640), 1.3),
      ('landscape at 2x text', const Size(568, 320), 2.0),
    ]) {
      testWidgets('no overflow through a whole lesson: $name', (tester) async {
        final skill = drillCurriculum.first;
        final lesson = skill.lessons.first;
        await _boot(
          tester,
          DrillLessonScreen(
            lesson: lesson,
            skill: skill,
            look: AssistantLook.sol,
            progress: DrillProgressStore(),
            onPracticeAloud: () {},
          ),
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        var right = false;
        while (find.text('Lesson complete').evaluate().isEmpty) {
          // Alternate wrong and right, so both feedback panels and the second tries are laid out.
          await _answer(tester, _current(tester), right: right);
          expect(tester.takeException(), isNull, reason: _current(tester).id);
          right = !right;
          await _continue(tester);
          expect(tester.takeException(), isNull);
        }
        expect(find.byKey(const ValueKey('drill-done')), findsOneWidget);
        expect(find.byKey(const ValueKey('drill-aloud')), findsOneWidget);
        await tester.ensureVisible(find.text('Lesson complete'));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('no overflow on the skill path and Home card at 1.3x text on a small phone', (tester) async {
      final progress = DrillProgressStore();
      await progress.complete('intro-1', 4, 5);
      await _boot(
        tester,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(Space.gutter),
            children: [
              NextLessonCard(progress: progress, onOpen: (_, _) {}),
              const SizedBox(height: Space.x3),
              SkillPath(progress: progress, onOpenLesson: (_, _) {}),
            ],
          ),
        ),
        size: const Size(360, 640),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
