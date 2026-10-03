import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/assistant.dart';
import 'package:prepsuite/app/profile.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/app/session.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/contracts.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/design/assistant_avatar.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/features/interview/interview_screen.dart';
import 'package:prepsuite/features/intake/intake_screen.dart';
import 'package:prepsuite/features/onboarding/onboarding_flow.dart';
import 'package:prepsuite/features/profile/profile_screen.dart';
import 'package:prepsuite/features/shell/app_shell.dart';
import 'package:prepsuite/features/talk/talk_screen.dart';
import 'package:prepsuite/features/wrapup/wrapup_screen.dart';

class _Phone {
  const _Phone(this.name, this.size, {this.scale = 1, this.ratio = 2});

  final String name;
  final Size size;
  final double scale;
  final double ratio;

  double get keyboardHeight => size.height < 400 ? 180 : 250;

  /// A portrait phone at the default text size: the practice's next action must sit in the pinned
  /// bottom bar, in reach without scrolling.
  bool get pinsActions => scale == 1 && size.height > size.width;
}

const _phones = [
  _Phone('small 320x568', Size(320, 568)),
  _Phone('typical 390x844', Size(390, 844), ratio: 3),
  _Phone('large 430x932', Size(430, 932), ratio: 3),
  _Phone('landscape 568x320', Size(568, 320)),
  _Phone('small 320x568 text 2', Size(320, 568), scale: 2),
  _Phone('compact 360x640 text 2', Size(360, 640), scale: 2),
  _Phone('typical 390x844 text 2', Size(390, 844), scale: 2, ratio: 3),
  _Phone('landscape 568x320 text 2', Size(568, 320), scale: 2),
  _Phone('small 320x568 text 3', Size(320, 568), scale: 3),
  _Phone('landscape 568x320 text 3', Size(568, 320), scale: 3),
];

const _job = 'Graduate civil engineer designing bridges and community projects';
const _answer =
    'During a community rebuilding project I checked the design, '
    'explained the changes to volunteers and helped the team finish safely.';
const _feedback = AnswerFeedback(
  headline: 'A clear example with a specific result.',
  problem: 'Explain the decision you made and why it mattered to the team.',
  evidence: 'I explained the changes to volunteers.',
  fix: 'Name the change you proposed, then explain the result.',
  delivery: '',
  strength: 'You kept the example relevant to the job.',
  mock: true,
);
const _notes = Wrapup(
  tips: ['Name a specific decision and explain the result.'],
  lastMinuteNotes: [
    'Choose one example of helping a team solve a problem under pressure.',
    'Explain what you did personally and how you checked the outcome.',
  ],
  storiesToUse: ['Your community rebuilding project with volunteers.'],
  mock: true,
);

/// Speech is immediate here: these tests exercise layout and interaction, not audio timing.
class _ImmediateVoice implements InterviewerVoice {
  @override
  Stream<double> get level => const Stream.empty();

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}

AppServices _services({bool onboarded = true}) => AppServices(
  coach: FakeCoachApi(latency: Duration.zero),
  speech: FakeSpeechCapture(),
  voice: _ImmediateVoice(),
  consent: MemoryConsentStore(value: true),
  mic: GrantedMicPermission(),
  coachLabel: 'test',
  speechLabel: 'test',
  assistant: AssistantStore(onboarded: onboarded),
  profile: ProfileStore(
    initial: Profile(
      name: 'Alexandra',
      targetRole: _job,
      interviewDate: DateTime.now().add(const Duration(days: 7)),
      experience: ExperienceLevel.careerChange,
      about:
          'I studied engineering and volunteered on community rebuilding '
          'projects. I enjoy explaining technical ideas to a team.',
    ),
  ),
);

PracticeSession _session({bool typing = false, bool completed = false}) {
  final session = PracticeSession(
    job: _job,
    preferTyping: typing,
    set: const QuestionSet(
      jobTitle: _job,
      mock: true,
      questions: [
        CoachQuestion(
          id: 'q1',
          text: 'Tell me about a time you helped a team solve a difficult problem.',
          focus: 'Your actions and the result.',
        ),
      ],
    ),
  );
  if (completed) {
    session.answers[0] = const AnswerRecord(
      transcript: _answer,
      metrics: null,
      feedback: _feedback,
      typed: true,
    );
    session.wrapup = _notes;
  }
  return session;
}

bool _fontLoaded = false;
final _flutterErrorDetails = <FlutterErrorDetails>[];

Future<void> _mount(
  WidgetTester tester,
  _Phone phone,
  Widget screen,
  AppServices services,
) async {
  HologramVideo.instance.enabled = false;
  AssistantAvatar.live = false;
  if (!_fontLoaded) {
    await tester.runAsync(() async {
      final loader = FontLoader('MonaSans')
        ..addFont(rootBundle.load('assets/fonts/MonaSans.ttf'));
      await loader.load();
    });
    _fontLoaded = true;
  }
  _flutterErrorDetails.clear();
  final originalHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    _flutterErrorDetails.add(details);
    originalHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalHandler);
  tester.view.devicePixelRatio = phone.ratio;
  tester.view.physicalSize = phone.size * phone.ratio;
  final safeTop = phone.size.height < 400 ? 0.0 : 24.0;
  tester.view.padding = FakeViewPadding(
    top: safeTop * phone.ratio,
    bottom: 16 * phone.ratio,
  );
  tester.view.viewPadding = FakeViewPadding(
    top: safeTop * phone.ratio,
    bottom: 16 * phone.ratio,
  );
  tester.platformDispatcher.textScaleFactorTestValue = phone.scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(theme: prepTheme(), home: screen),
    ),
  );
  await _pump(tester);
  _expectNoFlutterErrors(tester, '${phone.name}: ${screen.runtimeType}');
}

Future<void> _pump(WidgetTester tester, [int milliseconds = 500]) async {
  // Bounded pumping: microphone timers must not make these tests wait forever.
  for (var elapsed = 0; elapsed < milliseconds; elapsed += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _expectNoFlutterErrors(WidgetTester tester, String checkpoint) {
  final errors = <Object>[];
  Object? error;
  while ((error = tester.takeException()) != null) {
    errors.add(error!);
  }
  expect(
    errors,
    isEmpty,
    reason:
        '$checkpoint\n${errors.join('\n\n')}\n'
        '${_flutterErrorDetails.map((details) => details.toString()).join('\n\n')}',
  );
  _flutterErrorDetails.clear();
}

Future<void> _tap(WidgetTester tester, Finder target, String checkpoint) async {
  // Let caret scrolling finish before a user scrolls to a different control.
  await _pump(tester, 300);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      150,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await _pump(tester, 100);
  _expectNoFlutterErrors(tester, '$checkpoint: scrolling to action');
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason:
        '$checkpoint: action must be reachable; '
        'rect=${tester.getRect(target)}; '
        'size=${tester.view.physicalSize / tester.view.devicePixelRatio}; '
        'keyboard=${tester.view.viewInsets.bottom / tester.view.devicePixelRatio}',
  );
  await tester.tap(target);
  await _pump(tester);
  _expectNoFlutterErrors(tester, checkpoint);
}

Future<void> _keyboard(
  WidgetTester tester,
  _Phone phone, {
  bool visible = true,
}) async {
  tester.view.viewInsets = FakeViewPadding(
    bottom: visible ? phone.keyboardHeight * phone.ratio : 0,
  );
  await _pump(tester);
  _expectNoFlutterErrors(
    tester,
    '${phone.name}: keyboard ${visible ? 'open' : 'closed'}',
  );
}

void main() {
  for (final phone in _phones) {
    group(phone.name, () {
      testWidgets('all shell tabs and saved history remain usable', (
        tester,
      ) async {
        final services = _services();
        await services.sessions.finished(_session(completed: true));
        await _mount(tester, phone, const AppShell(), services);
        expect(
          tester.getSize(find.byKey(const ValueKey('tab-home'))).height,
          lessThanOrEqualTo(96),
          reason: 'navigation must leave room for content at large text sizes',
        );
        for (final tab in ['practice', 'history', 'profile', 'home']) {
          await _tap(tester, find.byKey(ValueKey('tab-$tab')), '$tab tab');
        }
        await _tap(
          tester,
          find.byKey(const ValueKey('start-practice')),
          'start practice',
        );
        expect(find.byType(IntakeScreen), findsOneWidget);
      });

      testWidgets(
        'onboarding coach picker and chat support keyboard and large text',
        (tester) async {
          final services = _services(onboarded: false);
          await _mount(tester, phone, OnboardingFlow(onDone: () {}), services);
          await _tap(
            tester,
            find.byKey(const ValueKey('onboarding-continue')),
            'onboarding continue',
          );
          await _tap(tester, find.text('Type instead'), 'onboarding typing');
          await _keyboard(tester, phone);
          for (final text in ['Alexandra', _job, _answer]) {
            await tester.enterText(
              find.byKey(const ValueKey('onboarding-field')),
              text,
            );
            await _pump(tester, 100);
            _expectNoFlutterErrors(tester, 'onboarding answer');
            await _tap(
              tester,
              find.byKey(const ValueKey('onboarding-send')),
              'onboarding send',
            );
          }
          await _keyboard(tester, phone, visible: false);
          await _tap(
            tester,
            find.byKey(const ValueKey('onboarding-done')),
            'onboarding finish',
          );
          expect(services.assistant.onboarded, isTrue);
        },
      );

      testWidgets(
        'voice job intake and editable transcript fit with a keyboard',
        (tester) async {
          await _mount(tester, phone, const IntakeScreen(), _services());
          final record = find.byKey(const ValueKey('record-button'));
          await _tap(tester, record, 'job record');
          await _tap(tester, record, 'job stop');
          expect(find.byKey(const ValueKey('job-field')), findsOneWidget);
          await _keyboard(tester, phone);
          await tester.enterText(find.byKey(const ValueKey('job-field')), _job);
          await _pump(tester, 100);
          _expectNoFlutterErrors(tester, 'edited job');
          await _tap(tester, find.text('Use this'), 'submit job with keyboard');
          expect(find.byType(InterviewScreen), findsOneWidget);
        },
      );

      testWidgets(
        'voice answer recording and transcript review remain reachable',
        (tester) async {
          await _mount(
            tester,
            phone,
            InterviewScreen(session: _session()),
            _services(),
          );
          final record = find.byKey(const ValueKey('record-button'));
          if (phone.pinsActions) {
            expect(record.hitTestable(), findsOneWidget, reason: '${phone.name}: record control without scrolling');
          }
          await _tap(tester, record, 'answer record');
          await _tap(tester, record, 'answer stop');
          expect(
            find.byKey(const ValueKey('answer-review-field')),
            findsOneWidget,
          );
          await _keyboard(tester, phone);
          await tester.enterText(
            find.byKey(const ValueKey('answer-review-field')),
            _answer,
          );
          await _pump(tester, 100);
          _expectNoFlutterErrors(tester, 'edited spoken answer');
          await _tap(tester, find.text('Get feedback'), 'confirm transcript');
          await _keyboard(tester, phone, visible: false);
          await _tap(
            tester,
            find.text('See your notes'),
            'spoken interview notes',
          );
          expect(find.byType(WrapupScreen), findsOneWidget);
        },
      );

      testWidgets(
        'typed answer, feedback, ask coach and final notes remain usable',
        (tester) async {
          await _mount(
            tester,
            phone,
            InterviewScreen(session: _session(typing: true)),
            _services(),
          );
          await _keyboard(tester, phone);
          await tester.enterText(
            find.byKey(const ValueKey('answer-field')),
            _answer,
          );
          await _pump(tester, 100);
          _expectNoFlutterErrors(tester, 'typed answer');
          await _tap(tester, find.text('Send'), 'send typed answer');
          await _keyboard(tester, phone, visible: false);
          if (phone.pinsActions) {
            expect(
              find.text('See your notes').hitTestable(),
              findsOneWidget,
              reason: '${phone.name}: the next step stays in view under long feedback',
            );
          }
          await _tap(tester, find.text('Ask'), 'open coach panel');
          await _keyboard(tester, phone);
          final coachField = find.byKey(const ValueKey('ask-field'));
          await tester.enterText(
            coachField,
            'How can I explain the result more clearly?',
          );
          await _pump(tester, 100);
          _expectNoFlutterErrors(tester, 'typed coach question');
          await _tap(tester, find.text('Send question'), 'send coach question');
          await _keyboard(tester, phone, visible: false);
          await _tap(
            tester,
            find.text('See your notes'),
            'typed interview notes',
          );
          expect(find.byType(WrapupScreen), findsOneWidget);
          await _tap(tester, find.text('Done'), 'notes done');
        },
      );

      testWidgets(
        'talk voice controls and typing conversation fit short screens',
        (tester) async {
          await _mount(tester, phone, const TalkScreen(), _services());
          await _tap(tester, find.text('Type instead'), 'talk typing');
          await _keyboard(tester, phone);
          await tester.enterText(
            find.byKey(const ValueKey('talk-field')),
            'How do I explain my project in an interview?',
          );
          await _pump(tester, 100);
          _expectNoFlutterErrors(tester, 'talk typed question');
          await _tap(tester, find.text('Send'), 'talk send');
          await _keyboard(tester, phone, visible: false);
          expect(
            find.textContaining('How do I explain my project'),
            findsOneWidget,
          );
          await _tap(tester, find.text('Speak instead'), 'talk voice');
        },
      );

      testWidgets('profile edit sheets scroll to save above the keyboard', (
        tester,
      ) async {
        final services = _services();
        await _mount(tester, phone, const ProfileScreen(), services);
        await _tap(tester, find.text('Name'), 'edit name and job');
        await _keyboard(tester, phone);
        await tester.enterText(
          find.byKey(const ValueKey('profile-name')),
          'Alexandra Lee',
        );
        await _tap(tester, find.text('Save'), 'save name and job');
        await _keyboard(tester, phone, visible: false);
        expect(services.profile.value.name, 'Alexandra Lee');
        await _tap(tester, find.text('Edit'), 'edit about');
        await _keyboard(tester, phone);
        await tester.enterText(
          find.byKey(const ValueKey('about-field')),
          _answer,
        );
        await _tap(tester, find.text('Save'), 'save about');
        await _keyboard(tester, phone, visible: false);
        expect(services.profile.value.about, _answer);
        await _tap(tester, find.text('Say it'), 'profile voice sheet');
        final record = find.byKey(const ValueKey('record-button'));
        await _tap(tester, record, 'profile record');
        await _tap(tester, record, 'profile stop recording');
        expect(services.profile.value.about, startsWith(_answer));
        await _tap(tester, find.text('Privacy'), 'profile privacy');
        await _tap(tester, find.text('Close'), 'privacy close');
      });
    });
  }
}
