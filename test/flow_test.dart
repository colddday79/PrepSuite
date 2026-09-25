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
import 'package:prepsuite/design/components.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/features/common/coach_widgets.dart';

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

class _GatedConsent extends MemoryConsentStore {
  _GatedConsent({super.value});

  Completer<void>? gate;

  @override
  Future<bool> accepted() async {
    await gate?.future;
    return super.accepted();
  }
}

class _Rig {
  _Rig({int questionFailures = 0, int feedbackFailures = 0, int wrapupFailures = 0, bool consented = false, MicAccess mic = MicAccess.granted, this.setup})
      : coach = _CoachSpy(questionFailures: questionFailures, feedbackFailures: feedbackFailures, wrapupFailures: wrapupFailures),
        speech = _TrackedSpeech(),
        voice = FakeInterviewerVoice(),
        consent = _GatedConsent(value: consented),
        micPermission = GrantedMicPermission(access: mic);

  final _CoachSpy coach;
  final _TrackedSpeech speech;
  final FakeInterviewerVoice voice;
  final _GatedConsent consent;
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


bool _fontsLoaded = false;

/// The real fonts, so overflow checks match the device.
Future<void> loadAppFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    await (FontLoader('BodoniModa')..addFont(rootBundle.load('assets/fonts/BodoniModa.ttf'))).load();
    await (FontLoader('Jost')..addFont(rootBundle.load('assets/fonts/Jost.ttf'))).load();
  });
  _fontsLoaded = true;
}

Future<void> _boot(WidgetTester tester, _Rig rig, {Size size = const Size(1080, 2400), double ratio = 2.625}) async {
  HologramVideo.instance.enabled = false;
  await loadAppFonts(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
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

/// Says the job on Home (the fake recogniser hears a barista job) and waits for the check step.
Future<void> _sayJob(WidgetTester tester) async {
  await _tap(tester, _record());
  await _settle(tester, 1200);
  await _tap(tester, _record()); // stop
  await _settle(tester, 400);
  expect(find.byKey(const ValueKey('job-field')), findsOneWidget);
}

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

/// A spoken session: the job said on Home, confirmed, and the first question on screen.
Future<void> _openInterview(WidgetTester tester, _Rig rig) async {
  await _boot(tester, rig);
  await _sayJob(tester);
  await _tap(tester, find.text('Use this'));
  await _settle(tester, 1800);
}

Future<void> _finishTypedPractice(WidgetTester tester, _Rig rig) async {
  await _boot(tester, rig);
  await _tap(tester, find.text('Type instead'));
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

/// Where the presence's video square is drawn, from the stage that paints it.
Rect _presenceRect(WidgetTester tester) {
  final stage = find.byType(HologramStage);
  final size = tester.widget<HologramStage>(stage).size;
  return Rect.fromCenter(center: tester.getRect(stage).center, width: size, height: size);
}

void main() {
  testWidgets('first run: consent, job by voice on Home, five answers with feedback, notes, home', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);

    // First-run consent sheet.
    await _settle(tester, 600);
    expect(find.text('Before you start'), findsOneWidget);
    await _tap(tester, find.text('Accept'));
    await _settle(tester, 600);
    expect(rig.consent.value, isTrue);

    // Home asks for the job and the kind of interview, and records it right there.
    expect(find.text("What's the interview for?"), findsOneWidget);
    await _tap(tester, _record());
    expect(rig.micPermission.requests, 1);
    await _settle(tester, 2000);
    expect(find.textContaining('s left'), findsOneWidget);
    expect(find.textContaining('barista'), findsOneWidget, reason: 'the words appear as they are heard');
    await _tap(tester, _record());
    await _settle(tester, 300);
    expect(find.text("Here's what we heard. Fix anything we got wrong."), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('group interview'));

    await _tap(tester, find.text('Use this'));
    expect(find.text('Writing questions for this role'), findsOneWidget);
    await _settle(tester, 1000);
    expect(rig.coach.jobs.single, contains('group interview'));

    // Interview: five questions, answered out loud.
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
        expect(find.text('Tap to answer. Up to 2 minutes.'), findsOneWidget);
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

    // Home again, ready for the next job, with this session's notes one tap away.
    expect(find.text("What's the interview for?"), findsOneWidget);
    expect(find.byKey(const ValueKey('job-field')), findsNothing);
    expect(find.text('Last-minute notes'), findsOneWidget);
  });

  testWidgets('Home: the presence fills about half the screen and nothing sits over it', (tester) async {
    for (final (size, ratio) in [(const Size(1080, 2400), 2.625), (const Size(1080, 2340), 2.8125), (const Size(720, 1560), 2.0)]) {
      final rig = _Rig(consented: true);
      await _boot(tester, rig, size: size, ratio: ratio);
      await _settle(tester, 400);
      final screen = size / ratio;
      final presence = _presenceRect(tester);
      expect(presence.height, greaterThanOrEqualTo(screen.height * 0.42), reason: '$screen');
      // The ring stays on screen; only the empty black corners of the video square may run past it.
      final circle = Rect.fromCenter(center: presence.center, width: presence.width * presenceRing, height: presence.height * presenceRing);
      expect(circle.left, greaterThanOrEqualTo(0), reason: 'ring on screen at $screen');
      expect(circle.right, lessThanOrEqualTo(screen.width), reason: 'ring on screen at $screen');
      // Every control and line of text sits clear of the presence: in its top corners or below it.
      for (final element in find.byWidgetPredicate((w) => w is Text || w is MicButton || w is IconAction).evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget).first);
        final inside = rect.bottom > circle.top && rect.top < circle.bottom && rect.right > circle.left && rect.left < circle.right;
        if (!inside) continue;
        // Corners of the square are outside the round presence.
        final nearest = Offset(circle.center.dx.clamp(rect.left, rect.right), circle.center.dy.clamp(rect.top, rect.bottom));
        expect((nearest - circle.center).distance, greaterThan(circle.width / 2), reason: '${element.widget} overlaps the presence at $screen');
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('silent answer: says so and lets you type instead', (tester) async {
    final rig = _Rig(consented: true);
    await _openInterview(tester, rig);

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
    await _tap(tester, find.text('Type instead'));
    await _settle(tester, 300);
    await tester.enterText(find.byKey(const ValueKey('job-field')), 'Junior web developer, technical interview');
    await tester.pump();
    await _tap(tester, find.text('Use this'));
    await _settle(tester, 600);
    expect(find.text("Couldn't get your questions."), findsOneWidget);
    expect(find.textContaining("Can't reach the coach"), findsOneWidget);

    await _tap(tester, find.text('Try again'));
    await _settle(tester, 1200);
    expect(find.textContaining('Question 1 of 5'), findsOneWidget);
    expect(rig.coach.jobs, ['Junior web developer, technical interview', 'Junior web developer, technical interview']);
  });

  testWidgets('a typed job can be changed after an error and is sent as typed', (tester) async {
    final rig = _Rig(consented: true, questionFailures: 1);
    await _boot(tester, rig);
    await _tap(tester, find.text('Type instead'));
    await _settle(tester, 300);
    await tester.enterText(find.byKey(const ValueKey('job-field')), 'Nurse');
    await tester.pump();
    await _tap(tester, find.text('Use this'));
    await _settle(tester, 600);
    await _tap(tester, find.text('Change the job'));
    await _settle(tester, 300);
    await tester.enterText(find.byKey(const ValueKey('job-field')), 'Nurse, panel interview');
    await tester.pump();
    await _tap(tester, find.text('Use this'));
    await _settle(tester, 1200);
    expect(rig.coach.jobs.last, 'Nurse, panel interview');
    // Typing the job means a quiet practice: the answer box is ready and nothing was recorded.
    expect(find.byKey(const ValueKey('answer-field')), findsOneWidget);
    expect(rig.speech.startCalls, 0);
  });

  testWidgets('Not now keeps you on Home; the mic asks again, and a blocked mic offers typing', (tester) async {
    final rig = _Rig(mic: MicAccess.blocked);
    await _boot(tester, rig);
    await _settle(tester, 600);
    await _tap(tester, find.text('Not now'));
    await _settle(tester, 600);
    expect(rig.consent.value, isFalse);
    expect(find.text("What's the interview for?"), findsOneWidget);

    await _tap(tester, _record());
    await _settle(tester, 600);
    expect(find.text('Before you start'), findsOneWidget);
    await _tap(tester, find.text('Accept'));
    await _settle(tester, 600);

    expect(find.text('The microphone is off.'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    expect(rig.speech.startCalls, 0);
  });

  testWidgets('declining consent from the mic sends nothing and stays ready', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);
    await _settle(tester, 600);
    await _tap(tester, find.text('Not now'));
    await _settle(tester, 600);
    await _tap(tester, _record());
    await _settle(tester, 600);
    await _tap(tester, find.text('Not now'));
    await _settle(tester, 600);
    expect(rig.micPermission.requests, 0);
    expect(rig.speech.startCalls, 0);
    expect(find.text('Tap and talk. You have 10 seconds.'), findsOneWidget);
  });

  testWidgets('job recording stops at ten seconds and sends only the confirmed role', (tester) async {
    final rig = _Rig(consented: true);
    await _boot(tester, rig);
    await _tap(tester, _record());
    await _settle(tester, 10300);

    expect(rig.speech.requestedDurations.single, const Duration(seconds: 10));
    expect(rig.speech.stopCalls, 1);
    expect(rig.speech.active, isFalse);
    expect(rig.coach.jobs, isEmpty);
    expect(find.byKey(const ValueKey('job-field')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('job-field')), 'Graduate civil engineer designing bridges, final round');
    await tester.pump();
    await _tap(tester, find.text('Use this'));
    await _settle(tester, 1000);
    expect(rig.coach.jobs, ['Graduate civil engineer designing bridges, final round']);
    expect(find.textContaining('Question 1 of 5'), findsOneWidget);
  });

  testWidgets('silent job is not sent to the coach and can be re-recorded', (tester) async {
    final rig = _Rig(consented: true);
    await _boot(tester, rig);
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

  testWidgets('pausing while the job is recorded keeps what was heard for checking', (tester) async {
    final rig = _Rig(consented: true);
    await _boot(tester, rig);
    await _tap(tester, _record());
    await _settle(tester, 1200);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(tester, 400);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester, 400);
    expect(rig.speech.active, isFalse);
    expect(find.byKey(const ValueKey('job-field')), findsOneWidget);
    expect(rig.coach.jobs, isEmpty);
  });

  testWidgets('rapid taps start one recording and send the job once', (tester) async {
    final rig = _Rig(consented: true);
    final mic = Completer<void>();
    rig.speech.startGate = mic;
    await _boot(tester, rig);
    await tester.tap(_record());
    await tester.tap(_record(), warnIfMissed: false);
    mic.complete();
    await _settle(tester, 1200);
    expect(rig.speech.startCalls, 1);
    await _tap(tester, _record()); // stop
    await _settle(tester, 300);

    // Even while the consent check is still answering, a second tap sends nothing more.
    final consent = Completer<void>();
    rig.consent.gate = consent;
    final use = find.text('Use this');
    await tester.tap(use);
    await tester.tap(use, warnIfMissed: false);
    consent.complete();
    await _settle(tester, 1200);
    expect(rig.coach.jobs, hasLength(1));
    expect(find.textContaining('Question 1 of 5'), findsOneWidget);
  });

  testWidgets('pending capture startup cannot leave a live microphone after the app is paused', (tester) async {
    final rig = _Rig(consented: true);
    final gate = Completer<void>();
    rig.speech.startGate = gate;
    await _boot(tester, rig);
    await _tap(tester, _record());
    await tester.pump();
    expect(rig.speech.startCalls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(tester, 300);

    gate.complete();
    await _settle(tester, 400);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester, 300);
    expect(rig.speech.active, isFalse);
    expect(rig.speech.cancelCalls, greaterThanOrEqualTo(1));
    expect(rig.coach.jobs, isEmpty);
    expect(find.text('Tap and talk. You have 10 seconds.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('microphone startup exception offers recovery instead of crashing', (tester) async {
    final rig = _Rig(consented: true);
    rig.speech.throwOnStart = true;
    await _boot(tester, rig);
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
    await _tap(tester, find.text('Finish your notes'));
    await _settle(tester, 1000);
    expect(rig.coach.wrapupCalls, hasLength(2));
    expect(rig.coach.wrapupCalls.last.map((a) => a.transcript), originals);
    expect(rig.coach.feedbackCalls, hasLength(5));
    expect(find.text('Tips'), findsOneWidget);
    expect(rig.services.sessions.last!.wrapup, isNotNull);
  });

  testWidgets('first launch shows real set-up progress, then the mic works', (tester) async {
    final gate = Completer<void>();
    final setup = SpeechSetup(prepareModels: (progress) async {
      progress(0.42);
      await gate.future;
    });
    final rig = _Rig(consented: true, setup: setup);
    await _boot(tester, rig);
    await _settle(tester, 300);
    expect(find.text('Setting up the voice on this phone'), findsOneWidget);
    expect(find.textContaining('42%'), findsOneWidget);
    await _tap(tester, _record());
    await _settle(tester, 300);
    expect(rig.speech.startCalls, 0, reason: 'the mic waits for the speech files');

    gate.complete();
    await _settle(tester, 1600);
    expect(find.text('Setting up the voice on this phone'), findsNothing);
    await _tap(tester, _record());
    await _settle(tester, 300);
    expect(rig.speech.startCalls, 1);
  });

  testWidgets('a build without speech models offers typing and says why', (tester) async {
    final setup = SpeechSetup(prepareModels: (_) async => throw const SpeechModelsMissing('no manifest'));
    final rig = _Rig(consented: true, setup: setup);
    await _boot(tester, rig);
    await _settle(tester, 600);
    expect(find.text("Voice isn't available."), findsOneWidget);
    expect(find.textContaining('offline speech files are missing'), findsOneWidget);

    await _tap(tester, find.text('Type the job'));
    await _settle(tester, 300);
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
