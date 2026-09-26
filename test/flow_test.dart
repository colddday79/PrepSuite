import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite_speech/prepsuite_speech.dart' show SpeechModelsMissing;
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/coach/contracts.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/coach/speech_adapter.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/features/intake/intake_screen.dart';

class _FeedbackCall {
  const _FeedbackCall(this.job, this.question, this.transcript, this.delivery);

  final String job;
  final String question;
  final String transcript;
  final DeliveryMetrics? delivery;
}

class _CoachSpy extends FakeCoachApi {
  _CoachSpy({int questionFailures = 0, this.feedbackFailures = 0, this.wrapupFailures = 0})
      : super(latency: const Duration(milliseconds: 300), failuresBeforeSuccess: questionFailures);

  int feedbackFailures;
  int wrapupFailures;
  final jobs = <String>[];
  final feedbackCalls = <_FeedbackCall>[];
  final wrapupCalls = <List<AnswerSummary>>[];

  @override
  Future<QuestionSet> questions({required String job, int count = 5}) {
    jobs.add(job);
    return super.questions(job: job, count: count);
  }

  @override
  Future<AnswerFeedback> feedback({required String job, required String question, required String transcript, DeliveryMetrics? delivery}) async {
    feedbackCalls.add(_FeedbackCall(job, question, transcript, delivery));
    if (feedbackFailures > 0) {
      feedbackFailures--;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      throw const CoachException(CoachErrorKind.offline);
    }
    return super.feedback(job: job, question: question, transcript: transcript, delivery: delivery);
  }

  @override
  Future<Wrapup> wrapup({required String job, required List<AnswerSummary> answers}) async {
    wrapupCalls.add(List.of(answers));
    if (wrapupFailures > 0) {
      wrapupFailures--;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      throw const CoachException(CoachErrorKind.offline);
    }
    return super.wrapup(job: job, answers: answers);
  }
}

class _TrackedSpeech extends FakeSpeechCapture {
  Completer<void>? startGate;
  bool throwOnStart = false;
  bool active = false;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  final requestedDurations = <Duration>[];

  @override
  Future<bool> start({required Duration maxDuration}) async {
    startCalls++;
    requestedDurations.add(maxDuration);
    if (throwOnStart) throw StateError('Microphone is busy');
    await startGate?.future;
    active = await super.start(maxDuration: maxDuration);
    return active;
  }

  @override
  Future<CaptureResult?> stop() async {
    stopCalls++;
    active = false;
    return super.stop();
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    active = false;
    await super.cancel();
  }
}

class _Rig {
  _Rig({int questionFailures = 0, int feedbackFailures = 0, int wrapupFailures = 0, bool consented = false, MicAccess mic = MicAccess.granted, this.setup})
      : coach = _CoachSpy(questionFailures: questionFailures, feedbackFailures: feedbackFailures, wrapupFailures: wrapupFailures),
        speech = _TrackedSpeech(),
        voice = FakeInterviewerVoice(),
        consent = MemoryConsentStore(value: consented),
        micPermission = GrantedMicPermission(access: mic);

  final _CoachSpy coach;
  final _TrackedSpeech speech;
  final FakeInterviewerVoice voice;
  final MemoryConsentStore consent;
  final GrantedMicPermission micPermission;
  final SpeechSetup? setup;

  late final services = AppServices(
    speechSetup: setup,
    coach: coach,
    speech: speech,
    voice: voice,
    consent: consent,
    mic: micPermission,
    coachLabel: 'test',
    speechLabel: 'test',
  );
}

bool _fontLoaded = false;

Future<void> _boot(WidgetTester tester, _Rig rig) async {
  HologramVideo.instance.enabled = false;
  if (!_fontLoaded) {
    // Real Mona Sans metrics, so overflow checks match the device.
    await tester.runAsync(() async {
      final loader = FontLoader('MonaSans')..addFont(rootBundle.load('assets/fonts/MonaSans.ttf'));
      await loader.load();
    });
    _fontLoaded = true;
  }
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PrepSuiteApp(services: rig.services));
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
  await _settle(tester, 1600); // let the interviewer finish the question
  await _tap(tester, _record());
  await _settle(tester, 1200);
  await _tap(tester, _record()); // stop
  await _settle(tester, 300);
  expect(find.byKey(const ValueKey('answer-review-field')), findsOneWidget);
}

Future<void> _answerOutLoud(WidgetTester tester) async {
  await _recordAnswer(tester);
  await _tap(tester, find.text('Get feedback'));
  await _settle(tester, 600);
}

Future<void> _openIntake(WidgetTester tester, _Rig rig) async {
  await _boot(tester, rig);
  await _tap(tester, find.text('Start practice'));
  await _settle(tester, 1600);
}

Future<void> _openInterview(WidgetTester tester, _Rig rig) async {
  await _openIntake(tester, rig);
  await _tap(tester, find.text('Type instead'));
  await _settle(tester, 300);
  await tester.enterText(find.byKey(const ValueKey('job-field')), 'Barista at a busy cafe');
  await tester.pump();
  await _tap(tester, find.text('Use this'));
  await _settle(tester, 1800);
}

Future<void> _finishTypedPractice(WidgetTester tester, _Rig rig) async {
  await _boot(tester, rig);
  await _tap(tester, find.text('Practise by typing'));
  await _settle(tester, 600);
  await tester.enterText(find.byKey(const ValueKey('job-field')), 'Barista at a busy cafe');
  await tester.pump();
  await _tap(tester, find.text('Use this'));
  await _settle(tester, 900);
  for (var i = 1; i <= 5; i++) {
    await tester.enterText(find.byKey(const ValueKey('answer-field')), 'I handled order $i by checking the ticket, remaking the drink and explaining the fix to the customer.');
    await tester.pump();
    await _tap(tester, find.text('Send answer'));
    await _settle(tester, 600);
    await _tap(tester, find.text(i == 5 ? 'See your notes' : 'Next question'));
    await _settle(tester, 900);
  }
}

void main() {
  testWidgets('first run: consent, job by voice, five answers with feedback, notes, home', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);

    // First-run consent sheet.
    await _settle(tester, 600);
    expect(find.text('Before you start'), findsOneWidget);
    await _tap(tester, find.text('Accept'));
    await _settle(tester, 600);
    expect(rig.consent.value, isTrue);

    // Home.
    expect(find.text('Start practice'), findsOneWidget);
    await _tap(tester, find.text('Start practice'));
    await _settle(tester, 800);

    // Intake: the interviewer asks, we record the job, then check what we heard.
    expect(find.text('What job are you preparing for?', findRichText: true), findsOneWidget);
    await _settle(tester, 600);
    await _tap(tester, _record());
    expect(rig.micPermission.requests, 1);
    await _settle(tester, 2000);
    expect(find.textContaining('s left'), findsOneWidget);
    await _tap(tester, _record());
    await _settle(tester, 300);
    expect(find.byKey(const ValueKey('job-field')), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('barista'));

    await _tap(tester, find.text('Use this'));
    expect(find.text('Writing questions for this role'), findsOneWidget);
    await _settle(tester, 1000);

    // Interview: five questions.
    for (var i = 1; i <= 5; i++) {
      expect(find.textContaining('Question $i of 5'), findsOneWidget);
      expect(find.textContaining('Sample questions'), findsOneWidget);
      await _answerOutLoud(tester);
      expect(find.text('Fix it'), findsOneWidget);
      expect(find.text('How it sounded'), findsOneWidget);
      if (i == 1) {
        // Retry once: the question comes back ready to record.
        await _tap(tester, find.text('Try this one again'));
        await _settle(tester, 300);
        expect(find.text('Up to 2 minutes'), findsOneWidget);
        await _answerOutLoud(tester);
      }
      await _tap(tester, find.text(i == 5 ? 'See your notes' : 'Next question'));
      await _settle(tester, 800);
    }

    // Wrap-up.
    expect(find.text('Before your interview'), findsOneWidget);
    await _settle(tester, 600);
    expect(find.text('Tips'), findsOneWidget);
    expect(find.textContaining('Start every answer with the point'), findsOneWidget);
    expect(find.text('Stories to use'), findsOneWidget);
    await _tap(tester, find.text('Done'));
    await _settle(tester, 800);

    // Home again, with the notes kept for this session.
    expect(find.text('Start practice'), findsOneWidget);
    expect(find.text('Last-minute notes'), findsOneWidget);
  });

  testWidgets('silent answer: says so and lets you type instead', (tester) async {
    final rig = _Rig(consented: true);
    await _boot(tester, rig);
    await _tap(tester, find.text('Start practice'));
    await _settle(tester, 1400);
    await _tap(tester, _record());
    await _settle(tester, 800);
    await _tap(tester, _record());
    await _settle(tester, 300);
    await _tap(tester, find.text('Use this'));
    await _settle(tester, 1000);

    await _settle(tester, 1600);
    await _tap(tester, _record());
    rig.speech.silentNext = true;
    await _settle(tester, 800);
    await _tap(tester, _record());
    await _settle(tester, 300);
    expect(find.text("We couldn't hear your answer."), findsOneWidget);

    await _tap(tester, find.text('Type instead'));
    await _settle(tester, 300);
    await tester.enterText(find.byKey(const ValueKey('answer-field')), 'I kept the queue moving by taking orders while my coworker made drinks.');
    await tester.pump();
    await _tap(tester, find.text('Send answer'));
    await _settle(tester, 600);
    expect(find.text('Next question'), findsOneWidget);
    expect(find.textContaining('typed'), findsWidgets);
  });

  testWidgets('coach unreachable: honest error, then retry works', (tester) async {
    final rig = _Rig(consented: true, questionFailures: 1);
    await _boot(tester, rig);
    await _tap(tester, find.text('Start practice'));
    await _settle(tester, 1400);
    await _tap(tester, find.text('Type instead'));
    await _settle(tester, 300);
    await tester.enterText(find.byKey(const ValueKey('job-field')), 'Junior web developer');
    await tester.pump();
    await _tap(tester, find.text('Use this'));
    await _settle(tester, 600);
    expect(find.text("Couldn't get your questions."), findsOneWidget);
    expect(find.textContaining("Can't reach the coach"), findsOneWidget);

    await _tap(tester, find.text('Try again'));
    await _settle(tester, 1200);
    expect(find.textContaining('Question 1 of 5'), findsOneWidget);
  });

  testWidgets('Not now keeps you on Home; microphone off offers typing', (tester) async {
    final rig = _Rig(mic: MicAccess.blocked);
    await _boot(tester, rig);
    await _settle(tester, 600);
    await _tap(tester, find.text('Not now'));
    await _settle(tester, 600);
    expect(rig.consent.value, isFalse);

    await _tap(tester, find.text('Start practice'));
    await _settle(tester, 600);
    expect(find.text('Before you start'), findsOneWidget);
    await _tap(tester, find.text('Accept'));
    await _settle(tester, 1600);

    await _tap(tester, _record());
    await _settle(tester, 300);
    expect(find.text('The microphone is off.'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('job recording stops at ten seconds and sends only the confirmed role', (tester) async {
    final rig = _Rig(consented: true);
    await _openIntake(tester, rig);
    await _tap(tester, _record());
    await _settle(tester, 10300);

    expect(rig.speech.requestedDurations.single, const Duration(seconds: 10));
    expect(rig.speech.stopCalls, 1);
    expect(rig.speech.active, isFalse);
    expect(rig.coach.jobs, isEmpty);
    expect(find.byKey(const ValueKey('job-field')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('job-field')), 'Graduate civil engineer designing bridges');
    await tester.pump();
    await _tap(tester, find.text('Use this'));
    await _settle(tester, 1000);
    expect(rig.coach.jobs, ['Graduate civil engineer designing bridges']);
    expect(find.textContaining('Question 1 of 5'), findsOneWidget);
  });

  testWidgets('silent job is not sent to the coach and can be re-recorded', (tester) async {
    final rig = _Rig(consented: true);
    await _openIntake(tester, rig);
    rig.speech.silentNext = true;
    await _tap(tester, _record());
    await _settle(tester, 600);
    await _tap(tester, _record());
    await _settle(tester, 300);
    expect(find.text("We couldn't hear that."), findsOneWidget);
    expect(rig.coach.jobs, isEmpty);

    await _tap(tester, _record());
    await _settle(tester, 600);
    await _tap(tester, _record());
    await _settle(tester, 300);
    expect(find.byKey(const ValueKey('job-field')), findsOneWidget);
    expect(rig.coach.jobs, isEmpty);
  });

  testWidgets('recorded answer waits for confirmation and preserves measured delivery', (tester) async {
    final rig = _Rig(consented: true);
    await _openInterview(tester, rig);
    await _recordAnswer(tester);
    expect(rig.coach.feedbackCalls, isEmpty);

    final reviewed = tester.widget<TextField>(find.byKey(const ValueKey('answer-review-field'))).controller!.text;
    await _tap(tester, find.text('Get feedback'));
    await _settle(tester, 600);
    expect(rig.coach.feedbackCalls.single.transcript, reviewed);
    expect(rig.coach.feedbackCalls.single.delivery, isNotNull);
    expect(find.text('How it sounded'), findsOneWidget);
  });

  testWidgets('correcting an answer sends the correction without mismatched voice metrics', (tester) async {
    final rig = _Rig(consented: true);
    await _openInterview(tester, rig);
    await _recordAnswer(tester);
    const corrected = 'I checked the order, remade the drink and gave the customer a clear apology. They thanked me and returned the next day.';
    await tester.enterText(find.byKey(const ValueKey('answer-review-field')), corrected);
    await tester.pump();
    expect(rig.coach.feedbackCalls, isEmpty);
    await _tap(tester, find.text('Get feedback'));
    await _settle(tester, 600);

    expect(rig.coach.feedbackCalls.single.transcript, corrected);
    expect(rig.coach.feedbackCalls.single.delivery, isNull);
    expect(find.textContaining('typed'), findsWidgets);
    expect(find.textContaining('words a minute'), findsNothing);
  });

  testWidgets('pausing during an answer releases capture and keeps a review without sending AI', (tester) async {
    final rig = _Rig(consented: true);
    await _openInterview(tester, rig);
    await _tap(tester, _record());
    await _settle(tester, 800);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(tester, 400);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester, 400);

    expect(rig.speech.active, isFalse);
    expect(find.byKey(const ValueKey('answer-review-field')), findsOneWidget);
    expect(rig.coach.feedbackCalls, isEmpty);
    await _tap(tester, find.text('Get feedback'));
    await _settle(tester, 600);
    expect(rig.coach.feedbackCalls, hasLength(1));
  });

  testWidgets('rapid Start practice taps open only one intake', (tester) async {
    final rig = _Rig(consented: true);
    await _boot(tester, rig);
    final start = find.text('Start practice');
    await tester.tap(start);
    await tester.tap(start, warnIfMissed: false);
    await _settle(tester, 800);
    expect(find.byType(IntakeScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('pending capture startup cannot leave a live microphone after navigation', (tester) async {
    final rig = _Rig(consented: true);
    final gate = Completer<void>();
    rig.speech.startGate = gate;
    await _openIntake(tester, rig);
    await _tap(tester, _record());
    expect(rig.speech.startCalls, 1);
    await tester.binding.handlePopRoute();
    await _settle(tester, 500);
    expect(find.text('Start practice'), findsOneWidget);

    gate.complete();
    await _settle(tester, 400);
    expect(rig.speech.active, isFalse);
    expect(rig.speech.cancelCalls, greaterThanOrEqualTo(1));
    expect(rig.coach.jobs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('microphone startup exception offers recovery instead of crashing', (tester) async {
    final rig = _Rig(consented: true);
    rig.speech.throwOnStart = true;
    await _openIntake(tester, rig);
    await _tap(tester, _record());
    await _settle(tester, 300);
    expect(find.text("The microphone didn't start."), findsOneWidget);
    expect(find.text('Type instead'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback outage retries the confirmed answer without recording again', (tester) async {
    final rig = _Rig(consented: true, feedbackFailures: 1);
    await _openInterview(tester, rig);
    await _answerOutLoud(tester);
    expect(find.text("Couldn't check your answer."), findsOneWidget);
    final original = rig.coach.feedbackCalls.single;
    final captures = rig.speech.startCalls;
    await _tap(tester, find.text('Try again'));
    await _settle(tester, 700);

    expect(rig.coach.feedbackCalls, hasLength(2));
    expect(rig.coach.feedbackCalls.last.transcript, original.transcript);
    expect(rig.coach.feedbackCalls.last.delivery, same(original.delivery));
    expect(rig.speech.startCalls, captures);
    expect(find.text('Next question'), findsOneWidget);
  });

  testWidgets('wrapup outage keeps five answers for a retry from Home', (tester) async {
    final rig = _Rig(consented: true, wrapupFailures: 1);
    await _finishTypedPractice(tester, rig);
    expect(find.text("Couldn't write your notes."), findsOneWidget);
    expect(rig.services.sessions.last!.answers, hasLength(5));
    expect(rig.services.sessions.last!.wrapup, isNull);
    final originals = rig.coach.wrapupCalls.single.map((a) => a.transcript).toList();

    await _tap(tester, find.text('Done'));
    await _settle(tester, 700);
    await _tap(tester, find.text('Finish your interview notes'));
    await _settle(tester, 1000);
    expect(rig.coach.wrapupCalls, hasLength(2));
    expect(rig.coach.wrapupCalls.last.map((a) => a.transcript), originals);
    expect(rig.coach.feedbackCalls, hasLength(5));
    expect(find.text('Tips'), findsOneWidget);
    expect(rig.services.sessions.last!.wrapup, isNotNull);
  });

  testWidgets('first launch shows real set-up progress, then the interviewer asks', (tester) async {
    final gate = Completer<void>();
    final setup = SpeechSetup(prepareModels: (progress) async {
      progress(0.42);
      await gate.future;
    });
    final rig = _Rig(consented: true, setup: setup);
    await _openIntake(tester, rig);
    expect(find.text('Setting up the voice on this phone'), findsOneWidget);
    expect(find.textContaining('42%'), findsOneWidget);
    expect(_record(), findsNothing);

    gate.complete();
    await _settle(tester, 1600);
    expect(find.text('Setting up the voice on this phone'), findsNothing);
    expect(_record(), findsOneWidget);
  });

  testWidgets('a build without speech models offers typing and says why', (tester) async {
    final setup = SpeechSetup(prepareModels: (_) async => throw const SpeechModelsMissing('no manifest'));
    final rig = _Rig(consented: true, setup: setup);
    await _openIntake(tester, rig);
    expect(find.text("Voice isn't available."), findsOneWidget);
    expect(find.textContaining('offline speech files are missing'), findsOneWidget);
    expect(find.byKey(const ValueKey('job-field')), findsOneWidget);
    expect(find.text('Say it instead'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('job-field')), 'Barista at a busy cafe');
    await tester.pump();
    await _tap(tester, find.text('Use this'));
    await _settle(tester, 1800);
    // Answers are typed too, and the interviewer never tried to record.
    expect(find.byKey(const ValueKey('answer-field')), findsOneWidget);
    expect(rig.speech.startCalls, 0);
  });

  test('fake coach says it is a sample', () async {
    final health = await FakeCoachApi(latency: Duration.zero).health();
    expect(health.ok, isTrue);
    expect(health.mock, isTrue);
  });
}
