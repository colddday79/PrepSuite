import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/profile.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/design/assistant_avatar.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/features/home/home_screen.dart';
import 'package:prepsuite/features/intake/intake_screen.dart';
import 'package:prepsuite/features/practice/practice_screen.dart';
import 'package:prepsuite/features/profile/profile_screen.dart';

bool _fontLoaded = false;

AppServices _services({Profile profile = const Profile()}) => AppServices(
  coach: FakeCoachApi(latency: Duration.zero),
  speech: FakeSpeechCapture(),
  voice: FakeInterviewerVoice(),
  consent: MemoryConsentStore(value: true),
  mic: GrantedMicPermission(),
  profile: ProfileStore(initial: profile),
  coachLabel: 'test',
  speechLabel: 'test',
);

Future<void> _boot(WidgetTester tester, {Size physical = const Size(1080, 2340), double ratio = 2.625, AppServices? services}) async {
  HologramVideo.instance.enabled = false;
  AssistantAvatar.live = false;
  if (!_fontLoaded) {
    await tester.runAsync(() async {
      final loader = FontLoader('MonaSans')..addFont(rootBundle.load('assets/fonts/MonaSans.ttf'));
      await loader.load();
    });
    _fontLoaded = true;
  }
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PrepSuiteApp(services: services ?? _services()));
  await _settle(tester, 300);
}

Future<void> _settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('home greets by name and leads with the assistant and Start practice', (tester) async {
    await _boot(tester, services: _services(profile: const Profile(name: 'Alex')));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Hi, Alex'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-assistant')), findsOneWidget);
    expect(find.byKey(const ValueKey('start-practice')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a name it says hi there, and shows the interview countdown when set', (tester) async {
    final soon = DateTime.now().add(const Duration(days: 5));
    await _boot(tester, services: _services(profile: Profile(interviewDate: soon, targetRole: 'barista')));
    expect(find.text('Hi there'), findsOneWidget);
    expect(find.text('Interview in 5 days · barista'), findsOneWidget);
  });

  testWidgets('Start practice opens the job intake for five questions', (tester) async {
    await _boot(tester);
    await tester.tap(find.byKey(const ValueKey('start-practice')));
    await _settle(tester);
    final intake = tester.widget<IntakeScreen>(find.byType(IntakeScreen));
    expect(intake.questionCount, 5);
  });

  testWidgets('Quick question opens the intake for one question', (tester) async {
    await _boot(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('quick-question')));
    await tester.tap(find.byKey(const ValueKey('quick-question')));
    await _settle(tester);
    expect(tester.widget<IntakeScreen>(find.byType(IntakeScreen)).questionCount, 1);
  });

  testWidgets('the bottom bar switches tabs', (tester) async {
    await _boot(tester);
    await tester.tap(find.text('Practice').last);
    await _settle(tester, 400);
    expect(find.byType(PracticeScreen), findsOneWidget);
    await tester.tap(find.text('Profile').last);
    await _settle(tester, 400);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('no overflow with large text or on a small phone', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _boot(tester);
    expect(tester.takeException(), isNull);
    await _boot(tester, physical: const Size(720, 1280), ratio: 2);
    expect(tester.takeException(), isNull);
  });

  test('interview countdown wording', () {
    final now = DateTime(2026, 9, 25, 21);
    expect(interviewCountdown(const Profile(), now), isNull);
    expect(interviewCountdown(Profile(interviewDate: DateTime(2026, 9, 24)), now), isNull);
    expect(interviewCountdown(Profile(interviewDate: DateTime(2026, 9, 25)), now), 'Interview today');
    expect(interviewCountdown(Profile(interviewDate: DateTime(2026, 9, 26)), now), 'Interview tomorrow');
    expect(
      interviewCountdown(Profile(interviewDate: DateTime(2026, 10, 2), targetRole: 'junior analyst'), now),
      'Interview in 7 days · junior analyst',
    );
  });

  test('the fake coach still answers', () async {
    final set = await FakeCoachApi(latency: Duration.zero).questions(job: 'barista');
    expect(set.questions, isNotEmpty);
  });
}
