import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/assistant.dart';
import 'package:prepsuite/app/profile.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/contracts.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/design/assistant_avatar.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/features/talk/talk_screen.dart';

/// Norman, but every line he is given is written down and finishes on a fixed clock (60 ms a
/// word), so a test can pump past a greeting or an answer deterministically.
class _RecordingVoice implements InterviewerVoice {
  final spoken = <String>[];
  final _level = StreamController<double>.broadcast();
  Completer<void>? _playing;
  Timer? _timer;

  bool get speaking => _playing != null;

  @override
  Stream<double> get level => _level.stream;

  @override
  Future<void> speak(String text) {
    _cut();
    spoken.add(text);
    final done = Completer<void>();
    _playing = done;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    _level.add(0.6);
    _timer = Timer(Duration(milliseconds: 60 * words), () {
      _playing = null;
      _level.add(0);
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  @override
  Future<void> stop() async => _cut();

  void _cut() {
    _timer?.cancel();
    _timer = null;
    final playing = _playing;
    _playing = null;
    if (playing != null && !playing.isCompleted) playing.complete();
  }
}

class _AskCall {
  const _AskCall(this.job, this.userQuestion);
  final String job;
  final String userQuestion;
}

class _Coach extends FakeCoachApi {
  _Coach({this.askFailures = 0}) : super(latency: const Duration(milliseconds: 200));

  int askFailures;
  final asks = <_AskCall>[];

  @override
  Future<CoachReply> ask({String about = '', 
    required String job,
    required String userQuestion,
    String question = '',
    String answer = '',
    AnswerFeedback? feedback,
  }) async {
    asks.add(_AskCall(job, userQuestion));
    if (askFailures > 0) {
      askFailures--;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      throw const CoachException(CoachErrorKind.offline);
    }
    return super.ask(job: job, userQuestion: userQuestion, question: question, answer: answer, feedback: feedback);
  }
}

/// A short capture (15 s or less) hears [FakeSpeechCapture.jobText].
class _Speech extends FakeSpeechCapture {
  _Speech() : super(jobText: 'Is thirty seconds long enough to answer?');

  final durations = <Duration>[];

  @override
  Future<bool> start({required Duration maxDuration}) {
    durations.add(maxDuration);
    return super.start(maxDuration: maxDuration);
  }
}

class _Rig {
  _Rig({int askFailures = 0, String targetRole = 'Barista at a busy cafe', AssistantKind assistant = AssistantKind.nova})
    : coach = _Coach(askFailures: askFailures),
      assistantStore = AssistantStore(initial: assistant) {
    services = AppServices(
      coach: coach,
      speech: speech,
      voice: voice,
      consent: MemoryConsentStore(value: true),
      mic: mic,
      profile: ProfileStore(initial: Profile(targetRole: targetRole)),
      assistant: assistantStore,
      coachLabel: 'test',
      speechLabel: 'test',
    );
  }

  final _Coach coach;
  final speech = _Speech();
  final voice = _RecordingVoice();
  final mic = GrantedMicPermission();
  final AssistantStore assistantStore;
  late final AppServices services;
}

/// What the fake coach says about "…long…/…time…/…minute…" questions with no other context.
const _lengthReply = 'Aim for about a minute. Say your point first, give one real example, and finish with how it turned out.';

/// What it says about anything else asked with no question or answer context.
const _genericReply = 'Start with your point, back it up with one example from your own experience, and end with the result.';

bool _fontLoaded = false;

Future<void> _open(
  WidgetTester tester,
  _Rig rig, {
  double textScale = 1,
  Size physical = const Size(1080, 2340),
  double ratio = 2.625,
}) async {
  HologramVideo.instance.enabled = false;
  AssistantAvatar.live = false;
  // A fresh screen every time: reopening must not keep the last screen's state.
  await tester.pumpWidget(const SizedBox());
  if (!_fontLoaded) {
    // Real Mona Sans metrics, so overflow checks match the device.
    await tester.runAsync(() async {
      final loader = FontLoader('MonaSans')..addFont(rootBundle.load('assets/fonts/MonaSans.ttf'));
      await loader.load();
    });
    _fontLoaded = true;
  }
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      services: rig.services,
      child: MaterialApp(
        theme: prepTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const TalkScreen(),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester, [int ms = 700]) async {
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

Finder _record() => find.byKey(const ValueKey('record-button'));

void main() {
  testWidgets('greets once, then a typed question shows the answer and speaks it', (tester) async {
    final rig = _Rig();
    await _open(tester, rig);
    expect(find.text('Talk to Tide'), findsOneWidget);

    await _settle(tester, 1300); // the brief happy look, then the greeting plays out
    expect(rig.voice.spoken, ["Hi, I'm Tide. Ask me anything about your interview."]);

    await _tap(tester, find.text('Type instead'));
    await tester.enterText(find.byKey(const ValueKey('talk-field')), 'How long should my answer be?');
    await tester.pump();
    await _tap(tester, find.text('Send'));
    await _settle(tester, 500);

    expect(find.text('“How long should my answer be?”'), findsOneWidget);
    expect(find.text(_lengthReply), findsOneWidget);
    expect(find.text('Sample answer'), findsOneWidget);
    expect(rig.coach.asks.single.job, 'Barista at a busy cafe');
    expect(rig.voice.spoken.last, _lengthReply);
  });

  testWidgets('a voice question goes through the speech fake', (tester) async {
    final rig = _Rig();
    await _open(tester, rig);
    await _settle(tester, 1300);

    await _tap(tester, _record());
    expect(rig.mic.requests, 1);
    expect(rig.speech.durations.last, const Duration(seconds: 15));
    await _settle(tester, 600);
    expect(find.textContaining('s left'), findsOneWidget);

    await _tap(tester, _record()); // stop
    await _settle(tester, 500);

    expect(rig.coach.asks.single.userQuestion, 'Is thirty seconds long enough to answer?');
    expect(find.text('“Is thirty seconds long enough to answer?”'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a suggestion chip sends its question', (tester) async {
    final rig = _Rig();
    await _open(tester, rig);
    await _settle(tester, 1300);

    expect(find.text('How do I calm my nerves?'), findsOneWidget);
    await _tap(tester, find.text('How do I calm my nerves?'));
    await _settle(tester, 500);

    expect(rig.coach.asks.single.userQuestion, 'How do I calm my nerves?');
    expect(find.text('“How do I calm my nerves?”'), findsOneWidget);
    expect(find.text('What should I ask them?'), findsNothing); // chips gone once the talk starts
  });

  testWidgets('a coach error shows Try again, and retrying works', (tester) async {
    final rig = _Rig(askFailures: 1);
    await _open(tester, rig);
    await _settle(tester, 1300);

    await _tap(tester, find.text('How do I calm my nerves?'));
    await _settle(tester, 500);
    expect(find.text("Couldn't get an answer."), findsOneWidget);
    expect(find.textContaining("Can't reach the coach"), findsOneWidget);

    await _tap(tester, find.text('Try again'));
    await _settle(tester, 500);
    expect(rig.coach.asks, hasLength(2));
    expect(find.text("Couldn't get an answer."), findsNothing);
    expect(find.text(_genericReply), findsOneWidget);
  });

  testWidgets('no overflow with large text or on a small phone', (tester) async {
    final rig = _Rig();
    await _open(tester, rig, textScale: 1.3, physical: const Size(1080, 2160), ratio: 3);
    await _settle(tester, 1300);
    expect(tester.takeException(), isNull);

    await _tap(tester, find.text('Type instead'));
    await tester.enterText(find.byKey(const ValueKey('talk-field')), 'What should I wear to the interview?');
    await tester.pump();
    await _tap(tester, find.text('Send'));
    await _settle(tester, 500);
    expect(tester.takeException(), isNull);

    final small = _Rig();
    await _open(tester, small, physical: const Size(720, 1280), ratio: 2);
    await _settle(tester, 1300);
    expect(tester.takeException(), isNull);
    await _tap(tester, _record());
    await _settle(tester, 400);
    expect(tester.takeException(), isNull);
  });
}
