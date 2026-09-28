import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/assistant.dart';
import 'package:prepsuite/app/profile.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/design/assistant_avatar.dart';
import 'package:prepsuite/design/components.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/features/onboarding/onboarding_flow.dart';

/// Counts and records every greeting so the "spoken once" test doesn't just trust the fake.
class _TrackedVoice extends FakeInterviewerVoice {
  int speakCount = 0;
  final texts = <String>[];

  @override
  Future<void> speak(String text) async {
    speakCount++;
    texts.add(text);
    return super.speak(text);
  }
}

class _Rig {
  _Rig()
    : voice = _TrackedVoice(),
      consent = MemoryConsentStore(),
      assistant = AssistantStore(onboarded: false);

  final _TrackedVoice voice;
  final MemoryConsentStore consent;
  final AssistantStore assistant;
  final profile = ProfileStore();

  late final services = AppServices(
    coach: FakeCoachApi(),
    speech: FakeSpeechCapture(),
    voice: voice,
    consent: consent,
    mic: GrantedMicPermission(),
    coachLabel: 'test',
    speechLabel: 'test',
    profile: profile,
    assistant: assistant,
  );
}

bool _fontLoaded = false;

Future<void> _boot(
  WidgetTester tester,
  _Rig rig, {
  VoidCallback? onDone,
  double textScale = 1,
  Size size = const Size(411, 891),
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
    AppScope(
      services: rig.services,
      child: MaterialApp(
        theme: prepTheme(),
        debugShowCheckedModeBanner: false,
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: page!,
        ),
        home: OnboardingFlow(onDone: onDone ?? () {}),
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

/// Longer than Motion.enter (300ms), so an animated page change is always fully settled (and the
/// page it left is unmounted) before the next lookup by text runs.
const _pageSettle = 450;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Welcome (Start) through the three tutorial steps (Next x3), stopping on "Choose your
/// assistant".
Future<void> _reachChooseAssistant(WidgetTester tester) async {
  await _tap(tester, find.text('Start'));
  await _settle(tester, _pageSettle);
  await _tap(tester, find.text('Next'));
  await _settle(tester, _pageSettle);
  await _tap(tester, find.text('Next'));
  await _settle(tester, _pageSettle);
  await _tap(tester, find.text('Next'));
  await _settle(tester, _pageSettle);
}

/// Through "Choose your assistant" (keeping the default, Nova), stopping on "About you".
Future<void> _reachAboutYou(WidgetTester tester) async {
  await _reachChooseAssistant(tester);
  await _tap(tester, find.text('Choose Nova'));
  await _settle(tester, _pageSettle);
}

/// Through "About you" (Continue, without filling anything in), stopping on "Privacy".
Future<void> _reachPrivacy(WidgetTester tester) async {
  await _reachAboutYou(tester);
  await _tap(tester, find.text('Continue'));
  await _settle(tester, _pageSettle);
}

void main() {
  testWidgets('completing the flow calls finishOnboarding and onDone', (tester) async {
    final rig = _Rig();
    var done = false;
    await _boot(tester, rig, onDone: () => done = true);
    await _settle(tester, 900); // the welcome greeting

    await _reachPrivacy(tester);
    expect(find.text('Privacy'), findsOneWidget);
    expect(rig.assistant.onboarded, isFalse);
    expect(done, isFalse);

    await _tap(tester, find.text('Agree and start'));
    await _settle(tester, 300);

    expect(rig.assistant.onboarded, isTrue);
    expect(done, isTrue);
  });

  testWidgets('choosing a look updates the store', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);
    await _settle(tester, 900);
    await _reachChooseAssistant(tester);

    expect(find.text('Choose Nova'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('assistant-sol')));
    await _settle(tester, 300);

    expect(rig.assistant.value.kind, AssistantKind.sol);
    expect(find.text('Choose Sol'), findsOneWidget);
  });

  testWidgets('About you saves the profile', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);
    await _settle(tester, 900);
    await _reachAboutYou(tester);

    await tester.enterText(find.byKey(const ValueKey('onboarding-name')), 'Alex');
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('onboarding-role')), 'Junior barista');
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('onboarding-about')), 'I love coffee.');
    await tester.pump();

    await _tap(tester, find.text('Continue'));
    await _settle(tester, 300);

    expect(rig.profile.value.name, 'Alex');
    expect(rig.profile.value.targetRole, 'Junior barista');
    expect(rig.profile.value.about, 'I love coffee.');
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('Skip moves on without saving the profile', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);
    await _settle(tester, 900);
    await _reachAboutYou(tester);

    await tester.enterText(find.byKey(const ValueKey('onboarding-name')), 'Alex');
    await tester.pump();
    await _tap(tester, find.text('Skip'));
    await _settle(tester, 300);

    expect(rig.profile.value.isEmpty, isTrue);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('Agree accepts consent and finishes onboarding', (tester) async {
    final rig = _Rig();
    var done = false;
    await _boot(tester, rig, onDone: () => done = true);
    await _settle(tester, 900);
    await _reachPrivacy(tester);

    await _tap(tester, find.text('Agree and start'));
    await _settle(tester, 300);

    expect(rig.consent.value, isTrue);
    expect(rig.assistant.onboarded, isTrue);
    expect(done, isTrue);
  });

  testWidgets('Not now finishes onboarding without accepting consent', (tester) async {
    final rig = _Rig();
    var done = false;
    await _boot(tester, rig, onDone: () => done = true);
    await _settle(tester, 900);
    await _reachPrivacy(tester);

    await _tap(tester, find.text('Not now'));
    await _settle(tester, 300);

    expect(rig.consent.value, isFalse);
    expect(rig.assistant.onboarded, isTrue);
    expect(done, isTrue);
  });

  testWidgets('the voice greeting is spoken once', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);
    await _settle(tester, 900);

    expect(rig.voice.speakCount, 1);
    expect(rig.voice.texts.single, contains('Nova'));

    // Moving on and coming back with Back never speaks it again.
    await _tap(tester, find.text('Start'));
    await _settle(tester, _pageSettle);
    await _tap(tester, find.byWidgetPredicate((w) => w is IconAction && w.label == 'Back'));
    await _settle(tester, 300);

    expect(find.text("Hi, I'm Nova."), findsOneWidget);
    expect(rig.voice.speakCount, 1);
  });

  testWidgets('no overflow at 1.3x text on a small phone', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig, textScale: 1.3, size: const Size(360, 640));
    await _settle(tester, 900);
    expect(tester.takeException(), isNull);

    await _reachAboutYou(tester);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('onboarding-about')),
      'A longer description of myself that should wrap across several lines to check for overflow.',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await _tap(tester, find.text('Continue'));
    await _settle(tester, _pageSettle);
    expect(tester.takeException(), isNull);
  });
}
