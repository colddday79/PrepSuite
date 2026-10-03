import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/assistant.dart';
import 'package:prepsuite/app/profile.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/app/session.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/design/assistant_avatar.dart';
import 'package:prepsuite/design/components.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/design/icons.dart';
import 'package:prepsuite/design/tokens.dart';
import 'package:prepsuite/features/profile/practice_history.dart';
import 'package:prepsuite/features/profile/profile_format.dart';
import 'package:prepsuite/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _questions = [
  CoachQuestion(id: 'q1', text: 'Tell me about yourself.', focus: ''),
  CoachQuestion(id: 'q2', text: 'Why do you want this job?', focus: ''),
];

const _feedback = AnswerFeedback(
  headline: 'Good start.',
  problem: 'No result.',
  evidence: 'I made coffee.',
  fix: 'Say how it ended.',
  delivery: 'You typed this one.',
  strength: 'Clear.',
  mock: true,
);

const _notes = Wrapup(
  tips: ['Start with the point.'],
  lastMinuteNotes: ['Slow down on your first answer.'],
  storiesToUse: ['The mistake you fixed.'],
  mock: true,
);

PracticeSession _session({String title = 'Barista', DateTime? startedAt, int answered = 2, bool notes = false}) {
  final session = PracticeSession(
    job: '$title at a busy place',
    set: QuestionSet(jobTitle: title, questions: _questions, mock: true),
    startedAt: startedAt,
  );
  for (var i = 0; i < answered; i++) {
    session.answers[i] = const AnswerRecord(transcript: 'I made coffee.', metrics: null, feedback: _feedback, typed: true);
  }
  if (notes) session.wrapup = _notes;
  return session;
}

/// What the latest-practice key held before start times and history existed.
final _oldSave = {
  'job': 'Barista at a busy cafe',
  'set': {
    'job_title': 'Barista',
    'mock': true,
    'questions': [
      {'id': 'q1', 'text': 'Tell me about yourself.', 'focus': ''},
    ],
  },
  'answers': [
    {
      'index': 0,
      'transcript': 'I made coffee.',
      'typed': true,
      'feedback': {'headline': 'h', 'problem': 'p', 'evidence': 'e', 'fix': 'f', 'delivery': 'd', 'strength': 's', 'mock': true},
    },
  ],
  'wrapup': {'tips': ['Tip'], 'last_minute_notes': ['Breathe.'], 'stories_to_use': <String>[], 'mock': true},
};

Future<void> _flushWrites() => Future<void>.delayed(Duration.zero);

void main() {
  group('Profile', () {
    test('JSON round trip keeps every field', () {
      final profile = Profile(
        name: 'Alex',
        targetRole: 'Junior barista',
        interviewDate: DateTime(2026, 10, 2),
        experience: ExperienceLevel.careerChange,
        about: 'I love coffee and have volunteered at two community cafes.',
      );
      final back = Profile.fromJson(jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>);
      expect(back, profile);
      expect(Profile.fromJson(const Profile().toJson()), const Profile());
    });

    test('parsing tolerates missing, wrong and unknown values', () {
      expect(Profile.fromJson({}), const Profile());
      expect(
        Profile.fromJson({
          'name': 42,
          'target_role': ['x'],
          'interview_date': 'soon',
          'experience': 'astronaut',
          'about': 7,
        }),
        const Profile(),
      );
      final parsed = Profile.fromJson({
        'name': '  Alex ',
        'target_role': ' Nurse ',
        'interview_date': '2026-10-02T15:30:00Z',
        'experience': 'firstJob',
        'about': '  Loves solving problems.  ',
      });
      expect(parsed.name, 'Alex');
      expect(parsed.targetRole, 'Nurse');
      expect(parsed.interviewDate, DateTime(2026, 10, 2));
      expect(parsed.experience, ExperienceLevel.firstJob);
      expect(parsed.about, 'Loves solving problems.');
    });

    test('about counts towards isEmpty like every other field', () {
      expect(const Profile().isEmpty, isTrue);
      expect(const Profile(about: '  ').isEmpty, isTrue);
      expect(const Profile(about: 'Keen baker.').isEmpty, isFalse);
    });

    test('days until the interview count calendar days across daylight saving changes', () {
      // Clocks go forward on 29 March 2026 in Europe (a 23-hour day) and on 8 March in the US;
      // they go back on 25 October and 1 November.
      final march = Profile(interviewDate: DateTime(2026, 3, 30));
      expect(march.daysUntilInterview(DateTime(2026, 3, 28, 23, 30)), 2);
      expect(march.daysUntilInterview(DateTime(2026, 3, 29, 0, 30)), 1);
      expect(march.daysUntilInterview(DateTime(2026, 3, 30, 22)), 0);
      expect(march.daysUntilInterview(DateTime(2026, 3, 31, 1)), -1);
      expect(Profile(interviewDate: DateTime(2026, 3, 9)).daysUntilInterview(DateTime(2026, 3, 7, 12)), 2);
      expect(Profile(interviewDate: DateTime(2026, 10, 26)).daysUntilInterview(DateTime(2026, 10, 24, 23, 59)), 2);
      expect(Profile(interviewDate: DateTime(2026, 11, 2)).daysUntilInterview(DateTime(2026, 10, 31, 0, 1)), 2);
      expect(const Profile().daysUntilInterview(DateTime(2026, 3, 29)), isNull);
    });

    test('dates are written out in full, with the year only when it differs', () {
      final now = DateTime(2026, 9, 25);
      expect(shortDate(DateTime(2026, 9, 30), now), 'Wed, Sep 30');
      expect(shortDate(DateTime(2027, 1, 1), now), 'Fri, Jan 1, 2027');
      expect(spokenDate(DateTime(2026, 9, 30), now), 'Wednesday, September 30');
      expect(interviewDateLine(Profile(interviewDate: DateTime(2026, 9, 30)), now), 'Wed, Sep 30 · in 5 days');
      expect(interviewDateLine(Profile(interviewDate: DateTime(2026, 9, 26)), now), 'Sat, Sep 26 · tomorrow');
      expect(interviewDateLine(Profile(interviewDate: DateTime(2026, 9, 22)), now), 'Tue, Sep 22 · 3 days ago');
      expect(spokenInterviewDate(Profile(interviewDate: DateTime(2026, 9, 30)), now), 'Wednesday, September 30, in 5 days');
      expect(interviewDateLine(const Profile(), now), isNull);
    });
  });

  group('ProfileStore', () {
    test('saves to the phone, restores and clears', () async {
      SharedPreferences.setMockInitialValues({});
      final profile = Profile(
        name: 'Alex',
        interviewDate: DateTime(2026, 10, 2),
        experience: ExperienceLevel.firstJob,
        about: 'Keen baker.',
      );
      final store = ProfileStore(persist: true);
      await store.save(profile);
      expect(store.saveFailed, isFalse);
      expect((await SharedPreferences.getInstance()).getString('profile.v1'), isNotNull);

      final again = ProfileStore(persist: true);
      await again.restore();
      expect(again.value, profile);

      await again.clear();
      expect(again.value, const Profile());
      expect((await SharedPreferences.getInstance()).getString('profile.v1'), isNull);
      final empty = ProfileStore(persist: true);
      await empty.restore();
      expect(empty.value, const Profile());
    });

    test('an unreadable saved profile starts empty', () async {
      SharedPreferences.setMockInitialValues({'profile.v1': '{not json'});
      final store = ProfileStore(persist: true);
      await store.restore();
      expect(store.value, const Profile());
    });
  });

  group('SessionStore history', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saving a practice again, when its notes arrive, updates its one row', () async {
      final store = SessionStore();
      final session = _session();
      await store.finished(session);
      final first = store.history.single;
      expect(first.jobTitle, 'Barista');
      expect(first.startedAt, session.startedAt);
      expect((first.answered, first.total, first.hasNotes), (2, 2, false));

      session.wrapup = _notes;
      await store.finished(session);
      expect(store.history, hasLength(1));
      expect(store.history.single.hasNotes, isTrue);
      expect(store.history.single.finishedAt, first.finishedAt);
    });

    test('newest first, capped at the limit', () async {
      final store = SessionStore();
      final start = DateTime(2026, 9, 1, 9);
      for (var i = 0; i < SessionStore.historyLimit + 5; i++) {
        await store.finished(_session(title: 'Job $i', startedAt: start.add(Duration(hours: i))));
      }
      expect(store.history, hasLength(SessionStore.historyLimit));
      expect(store.history.first.jobTitle, 'Job 34');
      expect(store.history.last.jobTitle, 'Job 5');

      // An older practice saved late still sorts by when it started.
      await store.finished(_session(title: 'Late', startedAt: start.add(const Duration(hours: 20, minutes: 30))));
      expect(store.history.indexWhere((r) => r.jobTitle == 'Late'), 14);
      expect(store.history, hasLength(SessionStore.historyLimit));
    });

    test('history and the latest practice survive a restart', () async {
      final store = SessionStore(persist: true);
      final older = _session(title: 'Nurse', startedAt: DateTime(2026, 9, 20, 10), notes: true);
      final newer = _session(title: 'Barista', startedAt: DateTime(2026, 9, 24, 18, 5, 7, 123, 456), answered: 1);
      await store.finished(older);
      await store.finished(newer);

      final again = SessionStore(persist: true);
      await again.restore();
      expect(again.history, store.history);
      expect(again.history.map((r) => r.jobTitle), ['Barista', 'Nurse']);
      expect(again.last!.startedAt, newer.startedAt);
      expect(again.last!.answers, hasLength(1));
      expect(again.history.first.isFor(again.last!), isTrue);
    });

    test('a practice saved before history existed restores and starts the history', () async {
      SharedPreferences.setMockInitialValues({
        'interview.latest.v1': jsonEncode(_oldSave),
        'interview.history.v1': 'not json',
      });
      final store = SessionStore(persist: true);
      await store.restore();
      final last = store.last!;
      expect(last.jobTitle, 'Barista');
      expect(last.answers, hasLength(1));
      expect(last.wrapup, isNotNull);
      final record = store.history.single;
      expect(record.isFor(last), isTrue);
      expect(record.hasNotes, isTrue);
      expect(store.saveFailed, isFalse);

      // Later launches keep the start time it was given, so it stays one row.
      await _flushWrites();
      final again = SessionStore(persist: true);
      await again.restore();
      expect(again.last!.startedAt, last.startedAt);
      expect(again.history, store.history);
    });

    test('clear keeps the history; clearAll deletes both from the phone', () async {
      final store = SessionStore(persist: true);
      await store.finished(_session(notes: true));
      await store.clear();
      expect(store.last, isNull);
      expect(store.history, hasLength(1));

      await store.clearAll();
      expect(store.history, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('interview.latest.v1'), isNull);
      expect(prefs.getString('interview.history.v1'), isNull);
      final again = SessionStore(persist: true);
      await again.restore();
      expect(again.last, isNull);
      expect(again.history, isEmpty);
    });
  });

  group('ProfileScreen', () {
    testWidgets('empty: header, about card and settings, no back button, no history', (tester) async {
      await _openProfile(tester, _services());
      expect(find.bySemanticsLabel('Back'), findsNothing);
      expect(find.text('Your profile'), findsOneWidget);
      expect(find.text('Describe yourself in a few sentences.'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Say it'), findsOneWidget);
      expect(find.text('Sample answers'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Delete everything on this phone'), findsOneWidget);
      expect(find.byType(PracticeHistory), findsNothing);
      expect(find.text('No practices yet.'), findsNothing);
    });

    testWidgets('about: typing and saving shows the text and clears the empty state', (tester) async {
      final services = _services();
      await _openProfile(tester, services);

      await _tap(tester, find.text('Edit'));
      await _settle(tester, 300);
      await tester.enterText(
        find.byKey(const ValueKey('about-field')),
        'I study computer science and volunteer at a shelter.',
      );
      await tester.pump();
      await _tap(tester, find.text('Save'));
      await _settle(tester, 300);

      expect(services.profile.value.about, 'I study computer science and volunteer at a shelter.');
      expect(find.text('I study computer science and volunteer at a shelter.'), findsOneWidget);
      expect(find.text('Describe yourself in a few sentences.'), findsNothing);
    });

    testWidgets('about: saying it replaces empty text, then appends on the next recording', (tester) async {
      final services = _services();
      await _openProfile(tester, services);

      await _tap(tester, find.widgetWithText(QuietButton, 'Say it'));
      await _settle(tester, 300);
      final record = find.byKey(const ValueKey('record-button'));
      expect(record, findsOneWidget);
      await _tap(tester, record);
      await _settle(tester, 500);
      await _tap(tester, record);
      await _settle(tester, 300);

      final first = services.profile.value.about;
      expect(first, isNotEmpty);

      await _tap(tester, find.widgetWithText(QuietButton, 'Say it'));
      await _settle(tester, 300);
      await _tap(tester, record);
      await _settle(tester, 500);
      await _tap(tester, record);
      await _settle(tester, 300);

      final second = services.profile.value.about;
      expect(second, startsWith(first));
      expect(second.length, greaterThan(first.length));
    });

    testWidgets('details: name, job, date and experience save at once', (tester) async {
      final services = _services();
      await _openProfile(tester, services);

      await _tap(tester, find.text('Name'));
      await _settle(tester, 300);
      await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Alex');
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('profile-role')), 'Junior barista');
      await tester.pump();
      await _tap(tester, find.text('Save'));
      await _settle(tester, 300);
      expect(services.profile.value.name, 'Alex');
      expect(services.profile.value.targetRole, 'Junior barista');
      expect(find.text('Alex'), findsWidgets);
      expect(find.text('Junior barista'), findsWidgets);

      await _tap(tester, find.text('Some experience'));
      expect(services.profile.value.experience, ExperienceLevel.someExperience);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('experience-someExperience'))),
        isSemantics(label: 'Some experience', isChecked: true, isInMutuallyExclusiveGroup: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('experience-firstJob'))),
        isSemantics(label: 'First job', isChecked: false),
      );
      await _tap(tester, find.text('Changing careers'));
      expect(services.profile.value.experience, ExperienceLevel.careerChange);
      await _tap(tester, find.text('Changing careers'));
      expect(services.profile.value.experience, isNull);

      await _tap(tester, find.byKey(const ValueKey('profile-date')));
      await _settle(tester, 400);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      // The switch-to-typing control uses the app's hairline pencil, not a Material glyph.
      expect(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byWidgetPredicate((w) => w is PrepIcon && w.icon == PrepIcons.edit),
        ),
        findsOneWidget,
      );
      await _tap(tester, find.text('Save'));
      await _settle(tester, 400);
      final now = DateTime.now();
      expect(services.profile.value.interviewDate, DateTime(now.year, now.month, now.day));
      expect(find.textContaining('· today'), findsOneWidget);

      final remove = find.bySemanticsLabel('Remove interview date');
      expect(tester.getSemantics(remove), isSemantics(isButton: true, hasTapAction: true));
      await _tap(tester, remove);
      expect(services.profile.value.interviewDate, isNull);
      expect(find.text('Choose a date'), findsOneWidget);
      expect(services.profile.value.name, 'Alex');
    });

    testWidgets('choosing an assistant calls the store', (tester) async {
      final services = _services();
      await _openProfile(tester, services);
      expect(services.assistant.value.kind, AssistantKind.nova);
      await _tap(tester, find.byKey(const ValueKey('assistant-sol')));
      await _settle(tester, 300);
      expect(services.assistant.value.kind, AssistantKind.sol);
    });

    testWidgets('appearance: a swatch per theme, and choosing one calls the theme store', (tester) async {
      final services = _services();
      await _openProfile(tester, services);
      for (final theme in PrepThemes.all) {
        expect(find.byKey(ValueKey('theme-${theme.id}')), findsOneWidget);
      }
      expect(
        tester.getSemantics(find.byKey(const ValueKey('theme-ember'))),
        isSemantics(label: 'Ember theme', isChecked: true, isInMutuallyExclusiveGroup: true, hasTapAction: true),
      );
      await _tap(tester, find.byKey(const ValueKey('theme-signal')));
      await _settle(tester, 300);
      expect(services.theme.value, PrepThemes.signal);
      expect(tester.getSemantics(find.byKey(const ValueKey('theme-signal'))), isSemantics(isChecked: true));
      expect(tester.getSemantics(find.byKey(const ValueKey('theme-ember'))), isSemantics(isChecked: false));
    });

    testWidgets('see the introduction again resets onboarding', (tester) async {
      final services = _services();
      await _openProfile(tester, services);
      expect(services.assistant.onboarded, isTrue);
      await _tap(tester, find.text('See the introduction again'));
      await _settle(tester, 300);
      expect(services.assistant.onboarded, isFalse);
    });

    testWidgets('privacy opens the info-only consent sheet', (tester) async {
      await _openProfile(tester, _services());
      await _tap(tester, find.text('Privacy'));
      await _settle(tester, 300);
      expect(find.text('How your voice is used'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('delete everything only after confirming', (tester) async {
      final sessions = SessionStore();
      await sessions.finished(_session(title: 'Nurse', startedAt: DateTime(2026, 9, 20, 10), notes: true));
      final profile = ProfileStore(
        initial: const Profile(name: 'Alex', experience: ExperienceLevel.firstJob, about: 'I love coffee.'),
      );
      final services = _services(profile: profile, sessions: sessions);
      await _openProfile(tester, services);

      expect(find.text('Alex'), findsWidgets);
      await _tap(tester, find.text('Delete everything on this phone'));
      await _settle(tester, 300);
      expect(find.text('Delete everything on this phone?'), findsOneWidget);
      await _tap(tester, find.text('Cancel'));
      await _settle(tester, 300);
      expect(profile.value.name, 'Alex');
      expect(sessions.history, hasLength(1));

      await _tap(tester, find.text('Delete everything on this phone'));
      await _settle(tester, 300);
      await _tap(tester, find.text('Delete everything'));
      await _settle(tester, 300);
      expect(profile.value, const Profile());
      expect(sessions.last, isNull);
      expect(sessions.history, isEmpty);
      expect(find.text('Your details and practices are deleted.'), findsOneWidget);
      expect(find.text('Your profile'), findsOneWidget);
      expect(find.text('Describe yourself in a few sentences.'), findsOneWidget);
    });

    testWidgets('no overflow at 1.3x text, a full profile', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final profile = ProfileStore(
        initial: Profile(
          name: 'Alexandra',
          targetRole: 'Graduate civil engineer designing bridges',
          interviewDate: DateTime(DateTime.now().year + 1, 9, 30),
          experience: ExperienceLevel.careerChange,
          about:
              'I studied structural engineering and spent two summers volunteering on community '
              'rebuilding projects after storms.',
        ),
      );
      await _openProfile(tester, _services(profile: profile));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
      await _settle(tester, 300);
      expect(find.text('Delete everything on this phone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 360x640 dp and 1.3x text, an empty profile', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _openProfile(tester, _services(), physicalSize: const Size(360, 640), devicePixelRatio: 1);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
      await _settle(tester, 300);
      expect(find.text('Delete everything on this phone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

AppServices _services({ProfileStore? profile, SessionStore? sessions}) => AppServices(
  coach: FakeCoachApi(latency: Duration.zero),
  speech: FakeSpeechCapture(),
  voice: FakeInterviewerVoice(),
  consent: MemoryConsentStore(value: true),
  mic: GrantedMicPermission(),
  coachLabel: 'test',
  speechLabel: 'test',
  profile: profile,
  sessions: sessions,
);

bool _fontLoaded = false;

/// Mounts [ProfileScreen] as a tab body would see it: under the app's own theme and [AppScope],
/// with no navigator route around it (there is no back button to test around).
Future<void> _openProfile(
  WidgetTester tester,
  AppServices services, {
  Size physicalSize = const Size(1080, 2340),
  double devicePixelRatio = 2.625,
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
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: prepTheme(),
        theme: prepTheme(),
        home: const ProfileScreen(),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}
