import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/app/session.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/contracts.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/features/interview/interview_screen.dart';
import 'package:prepsuite/features/interview/read_aloud.dart';

/// Norman, but every line he is given is written down. A line "plays" for 60 ms a word unless
/// it is stopped or replaced first.
class _RecordingVoice implements InterviewerVoice {
  final spoken = <String>[];
  final events = <String>[];
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
    events.add('speak: $text');
    final done = Completer<void>();
    _playing = done;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    _level.add(0.6);
    _timer = Timer(Duration(milliseconds: 60 * words), () {
      _playing = null;
      _level.add(0);
      done.complete();
    });
    return done.future;
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    _cut();
  }

  void _cut() {
    _timer?.cancel();
    _timer = null;
    final playing = _playing;
    _playing = null;
    if (playing != null && !playing.isCompleted) playing.complete();
  }
}

class _AskCall {
  const _AskCall(this.job, this.userQuestion, this.question, this.answer, this.feedback);

  final String job;
  final String userQuestion;
  final String question;
  final String answer;
  final AnswerFeedback? feedback;
}

class _Coach extends FakeCoachApi {
  _Coach({this.askFailures = 0}) : super(latency: const Duration(milliseconds: 300));

  int askFailures;
  final asks = <_AskCall>[];

  @override
  Future<CoachReply> ask({required String job, required String userQuestion, String question = '', String answer = '', AnswerFeedback? feedback}) async {
    asks.add(_AskCall(job, userQuestion, question, answer, feedback));
    if (askFailures > 0) {
      askFailures--;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      throw const CoachException(CoachErrorKind.offline);
    }
    return super.ask(job: job, userQuestion: userQuestion, question: question, answer: answer, feedback: feedback);
  }
}

/// Short captures (the question to the coach) hear [FakeSpeechCapture.jobText].
class _Speech extends FakeSpeechCapture {
  _Speech() : super(jobText: 'How long should my answer be?');

  final durations = <Duration>[];
  int cancels = 0;

  @override
  Future<bool> start({required Duration maxDuration}) {
    durations.add(maxDuration);
    return super.start(maxDuration: maxDuration);
  }

  @override
  Future<void> cancel() {
    cancels++;
    return super.cancel();
  }
}

class _Rig {
  _Rig({bool preferTyping = false, int askFailures = 0})
      : coach = _Coach(askFailures: askFailures),
        session = PracticeSession(
          job: 'Barista at a busy cafe',
          preferTyping: preferTyping,
          set: const QuestionSet(
            jobTitle: 'Barista',
            mock: true,
            questions: [
              CoachQuestion(id: 'q1', text: 'Tell me about yourself.', focus: 'A short, relevant intro.'),
              CoachQuestion(id: 'q2', text: 'Why do you want this job?', focus: 'Real reasons that fit this role.'),
            ],
          ),
        );

  final _Coach coach;
  final PracticeSession session;
  final speech = _Speech();
  final voice = _RecordingVoice();
  final mic = GrantedMicPermission();

  late final services = AppServices(
    coach: coach,
    speech: speech,
    voice: voice,
    consent: MemoryConsentStore(value: true),
    mic: mic,
    coachLabel: 'test',
    speechLabel: 'test',
  );
}

/// What Norman says about a short answer from the fake coach: the headline, then the fix.
const _feedbackLine =
    'Too short to prove anything. Add one real example: what happened, what you did, and the result. Aim for 45 to 90 seconds.';
const _lengthReply = 'Aim for about a minute. Say your point first, give one real example, and finish with how it turned out.';
const _typedAnswer = 'I made the coffee and kept the queue moving.';

bool _fontLoaded = false;

Future<void> _open(WidgetTester tester, _Rig rig, {double textScale = 1}) async {
  HologramVideo.instance.enabled = false;
  if (!_fontLoaded) {
    // Real Jost and Bodoni Moda metrics, so overflow checks match the device.
    await tester.runAsync(() async {
      await (FontLoader('Jost')..addFont(rootBundle.load('assets/fonts/Jost.ttf'))).load();
      await (FontLoader('BodoniModa')..addFont(rootBundle.load('assets/fonts/BodoniModa.ttf'))).load();
    });
    _fontLoaded = true;
  }
  // A 360 dp wide phone for the large-text run, a roomier one otherwise.
  tester.view.physicalSize = textScale > 1 ? const Size(1080, 2160) : const Size(1080, 2400);
  tester.view.devicePixelRatio = textScale > 1 ? 3 : 2.625;
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
        home: InterviewScreen(session: rig.session),
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

Future<void> _recordAnswer(WidgetTester tester) async {
  await _settle(tester, 600); // Norman reads the question
  await _tap(tester, _record());
  await _settle(tester, 1200);
  await _tap(tester, _record()); // stop
  await _settle(tester, 300);
  await _tap(tester, find.text('Get feedback'));
  await _settle(tester, 400);
}

Future<void> _typeAnswer(WidgetTester tester) async {
  if (find.byKey(const ValueKey('answer-field')).evaluate().isEmpty) {
    await _tap(tester, find.text('Type instead'));
  }
  await tester.enterText(find.byKey(const ValueKey('answer-field')), _typedAnswer);
  await tester.pump();
  await _tap(tester, find.text('Send answer'));
  await _settle(tester, 400);
}

Future<void> _askByTyping(WidgetTester tester, String question) async {
  await _tap(tester, find.text('Ask the coach'));
  await _settle(tester, 400);
  if (find.byKey(const ValueKey('ask-field')).evaluate().isEmpty) {
    await _tap(tester, find.text('Type instead'));
  }
  await tester.enterText(find.byKey(const ValueKey('ask-field')), question);
  await tester.pump();
  await _tap(tester, find.text('Send question'));
}

void main() {
  test('spoken feedback is the headline then the fix, unquoted and at most 45 words', () {
    const quoted = AnswerFeedback(
      headline: '“You never said what you did.”',
      problem: 'You described the team, not yourself.',
      evidence: 'we fixed the rota',
      fix: '"Say I, then name two things you did yourself."',
      delivery: 'You spoke at 182 words a minute and used 4 filler words.',
      strength: 'A clear set-up.',
      mock: false,
    );
    expect(spokenFeedback(quoted), 'You never said what you did. Say I, then name two things you did yourself.');

    final long = AnswerFeedback(
      headline: 'Too long',
      problem: '',
      evidence: '',
      fix: 'Start with the result, then ${List.filled(60, 'more').join(' ')}',
      delivery: '',
      strength: '',
      mock: false,
    );
    final said = spokenFeedback(long);
    expect(said, startsWith('Too long. Start with the result, then'));
    expect(said, endsWith('.'));
    expect(said.split(' ').length, lessThanOrEqualTo(maxSpokenFeedbackWords));
  });

  testWidgets('a spoken session reads the feedback once, and Hear feedback reads it again', (tester) async {
    final rig = _Rig();
    await _open(tester, rig);
    await _recordAnswer(tester);

    expect(find.text('Fix it'), findsOneWidget);
    expect(rig.voice.spoken, ['Tell me about yourself.', _feedbackLine]);
    expect(find.text('Stop'), findsOneWidget);
    await _settle(tester, 2000);
    expect(rig.voice.spoken.where((line) => line == _feedbackLine), hasLength(1));
    expect(find.text('Hear feedback'), findsOneWidget);

    await _tap(tester, find.text('Hear feedback'));
    await _settle(tester, 100);
    expect(rig.voice.spoken.where((line) => line == _feedbackLine), hasLength(2));
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('a typing session stays quiet until Hear feedback, which Stop cuts off', (tester) async {
    final rig = _Rig(preferTyping: true);
    await _open(tester, rig);
    await _typeAnswer(tester);

    expect(find.text('Fix it'), findsOneWidget);
    await _settle(tester, 2000);
    expect(rig.voice.spoken, isEmpty);

    await _tap(tester, find.text('Hear feedback'));
    await _settle(tester, 100);
    expect(rig.voice.spoken, [_feedbackLine]);
    expect(rig.voice.speaking, isTrue);

    await _tap(tester, find.text('Stop'));
    expect(rig.voice.speaking, isFalse);
    expect(find.text('Hear feedback'), findsOneWidget);
  });

  testWidgets('asking by typing sends the context, shows the reply and reads it aloud', (tester) async {
    final rig = _Rig();
    await _open(tester, rig);
    await _typeAnswer(tester);
    await _askByTyping(tester, 'How long should this answer be?');

    expect(find.text('The coach is thinking'), findsOneWidget);
    expect(find.text('“How long should this answer be?”'), findsOneWidget);
    await _settle(tester, 400);

    expect(find.text(_lengthReply), findsOneWidget);
    expect(find.text('Sample answer'), findsOneWidget);
    expect(rig.voice.spoken.last, _lengthReply);
    expect(find.text('Next question'), findsOneWidget);

    final call = rig.coach.asks.single;
    expect(call.job, 'Barista at a busy cafe');
    expect(call.userQuestion, 'How long should this answer be?');
    expect(call.question, 'Tell me about yourself.');
    expect(call.answer, _typedAnswer);
    expect(call.feedback?.headline, 'Too short to prove anything.');

    // Another question starts from an empty field; Close puts the entry back.
    await _tap(tester, find.text('Ask another'));
    expect(find.byKey(const ValueKey('ask-field')), findsOneWidget);
    await _tap(tester, find.text('Close'));
    expect(find.byKey(const ValueKey('ask-field')), findsNothing);
    expect(find.text('Ask the coach'), findsOneWidget);
  });

  testWidgets('asking by voice records up to 15 seconds, at large text on a small phone', (tester) async {
    final rig = _Rig();
    await _open(tester, rig, textScale: 1.3);
    await _typeAnswer(tester);
    await _tap(tester, find.text('Ask the coach'));
    await _settle(tester, 400);

    await _tap(tester, _record());
    await _settle(tester, 1300);
    expect(rig.mic.requests, 1);
    expect(rig.speech.durations.last, const Duration(seconds: 15));
    expect(rig.voice.speaking, isFalse); // recording cut the feedback off
    expect(find.textContaining('s left'), findsOneWidget);
    expect(find.textContaining('How long should'), findsOneWidget);

    await _tap(tester, _record()); // stop
    await _settle(tester, 400);
    expect(rig.coach.asks.single.userQuestion, 'How long should my answer be?');
    expect(find.text('“How long should my answer be?”'), findsOneWidget);
    expect(find.text(_lengthReply), findsOneWidget);
    expect(rig.voice.spoken.last, _lengthReply);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unreachable coach says so plainly, and Try again asks again', (tester) async {
    final rig = _Rig(askFailures: 1);
    await _open(tester, rig);
    await _typeAnswer(tester);
    await _askByTyping(tester, 'How long should this answer be?');
    await _settle(tester, 400);

    expect(find.text("Couldn't get an answer."), findsOneWidget);
    expect(find.textContaining("Can't reach the coach"), findsOneWidget);
    await _tap(tester, find.text('Try again'));
    await _settle(tester, 400);
    expect(rig.coach.asks, hasLength(2));
    expect(rig.coach.asks.last.userQuestion, 'How long should this answer be?');
    expect(find.text(_lengthReply), findsOneWidget);
  });

  testWidgets('Next question stops Norman mid-feedback and drops a reply still on its way', (tester) async {
    final rig = _Rig();
    await _open(tester, rig);
    await _typeAnswer(tester);
    expect(rig.voice.speaking, isTrue);
    expect(rig.voice.spoken.last, _feedbackLine);

    await _askByTyping(tester, 'Should I mention my degree?');
    expect(find.text('The coach is thinking'), findsOneWidget);
    expect(rig.voice.speaking, isTrue); // still reading the feedback
    final before = rig.voice.events.length;
    await _tap(tester, find.text('Next question'));
    expect(rig.voice.events.skip(before).first, 'stop');

    await _settle(tester, 800);
    expect(rig.coach.asks, hasLength(1));
    expect(find.textContaining('Question 2 of 2'), findsOneWidget);
    expect(rig.voice.spoken.last, 'Why do you want this job?');
    expect(rig.voice.spoken.where((line) => line.startsWith('For this one')), isEmpty);
  });

  testWidgets('leaving the app while asking out loud drops the recording without asking the coach', (tester) async {
    final rig = _Rig();
    await _open(tester, rig);
    await _typeAnswer(tester);
    await _tap(tester, find.text('Ask the coach'));
    await _settle(tester, 400);
    await _tap(tester, _record());
    await _settle(tester, 600);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(tester, 200);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester, 400);

    expect(rig.speech.cancels, greaterThanOrEqualTo(1));
    expect(rig.coach.asks, isEmpty);
    expect(rig.voice.speaking, isFalse);
    expect(find.text('15 seconds'), findsOneWidget);
  });
}
