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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Types [text] into the answer bar and sends it, then lets the coach reply. Voice comes first, so
/// the first answer switches to typing.
Future<void> _answer(WidgetTester tester, String text) async {
  if (find.byKey(const ValueKey('onboarding-field')).evaluate().isEmpty) {
    await _tap(tester, find.byKey(const ValueKey('onboarding-type')));
  }
  await tester.enterText(find.byKey(const ValueKey('onboarding-field')), text);
  await tester.pump();
  await _tap(tester, find.byKey(const ValueKey('onboarding-send')));
  await _settle(tester, 1500);
}

/// Picks the default coach and goes into the conversation.
Future<void> _start(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('onboarding-continue')));
  await _settle(tester, 1500);
}

void main() {
  testWidgets('the whole conversation saves the answers and finishes', (tester) async {
    final rig = _Rig();
    var done = 0;
    await _boot(tester, rig, onDone: () => done++);
    expect(find.text('Choose your coach'), findsOneWidget);
    await _start(tester);
    expect(find.textContaining('What should I call you?'), findsOneWidget);

    await _answer(tester, 'Alex');
    expect(find.textContaining('Nice to meet you, Alex'), findsOneWidget);
    await _answer(tester, "I'm applying for a junior data analyst job at a hospital");
    await _answer(tester, 'Business student, good with Excel');
    expect(rig.profile.value.name, 'Alex');
    expect(rig.profile.value.targetRole, 'Junior data analyst job');
    expect(rig.profile.value.about, 'Business student, good with Excel');

    expect(find.textContaining("All set, Alex. Let's practice!"), findsOneWidget);
    // Privacy is asked before the first practice, not here.
    expect(rig.consent.value, isFalse);
    await _tap(tester, find.byKey(const ValueKey('onboarding-done')));
    await _settle(tester, 300);
    expect(rig.assistant.onboarded, isTrue);
    expect(done, 1);
  });

  testWidgets('choosing a coach updates the store', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);
    await _tap(tester, find.byKey(const ValueKey('assistant-mint')));
    await _settle(tester, 300);
    expect(rig.assistant.value.kind, AssistantKind.mint);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('the coach asks out loud, once per question', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);
    await _start(tester);
    expect(rig.voice.texts.where((t) => t.contains('What should I call you?')), hasLength(1));
  });

  testWidgets('about me can be skipped', (tester) async {
    final rig = _Rig();
    var done = 0;
    await _boot(tester, rig, onDone: () => done++);
    await _start(tester);
    await _answer(tester, 'Sam');
    await _answer(tester, 'Barista');
    await _tap(tester, find.text('Not now'));
    await _settle(tester, 1500);
    expect(rig.profile.value.about, '');
    await _tap(tester, find.byKey(const ValueKey('onboarding-done')));
    await _settle(tester, 300);
    expect(done, 1);
  });

  testWidgets('voice comes first, and typing is one tap away', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig);
    await _start(tester);
    expect(find.byKey(const ValueKey('onboarding-mic')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-field')), findsNothing);
    expect(find.text('Tap to answer'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('onboarding-type')));
    expect(find.byKey(const ValueKey('onboarding-field')), findsOneWidget);
    // The mic stays in the typing bar.
    expect(find.byKey(const ValueKey('onboarding-mic')), findsOneWidget);
  });

  testWidgets('Skip leaves onboarding straight away', (tester) async {
    final rig = _Rig();
    var done = 0;
    await _boot(tester, rig, onDone: () => done++);
    await _tap(tester, find.text('Skip'));
    await _settle(tester, 300);
    expect(rig.assistant.onboarded, isTrue);
    expect(done, 1);
  });

  testWidgets('no overflow at 1.3x text on a small phone', (tester) async {
    final rig = _Rig();
    await _boot(tester, rig, textScale: 1.3, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
    await _start(tester);
    expect(tester.takeException(), isNull);
    await _answer(tester, 'Alex');
    expect(tester.takeException(), isNull);
  });
}
