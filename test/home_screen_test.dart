import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/profile.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/design/components.dart';
import 'package:prepsuite/design/frosted_panel.dart';
import 'package:prepsuite/design/hologram.dart';
import 'package:prepsuite/features/history/history_screen.dart';
import 'package:prepsuite/features/home/home_screen.dart';
import 'package:prepsuite/features/profile/profile_screen.dart';

bool _fontLoaded = false;

AppServices _services({Profile profile = const Profile()}) => AppServices(
  coach: FakeCoachApi(),
  speech: FakeSpeechCapture(),
  voice: FakeInterviewerVoice(),
  consent: MemoryConsentStore(value: true),
  mic: GrantedMicPermission(),
  profile: ProfileStore(initial: profile),
  coachLabel: 'test',
  speechLabel: 'test',
);

Future<void> _boot(
  WidgetTester tester, {
  Size physical = const Size(1080, 2340),
  double ratio = 2.625,
  AppServices? services,
}) async {
  HologramVideo.instance.enabled = false;
  if (!_fontLoaded) {
    // Real Mona Sans metrics, so overflow checks match the device.
    await tester.runAsync(() async {
      final loader = FontLoader('MonaSans')
        ..addFont(rootBundle.load('assets/fonts/MonaSans.ttf'));
      await loader.load();
    });
    _fontLoaded = true;
  }
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PrepSuiteApp(services: services ?? _services()));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'the presence takes about half the screen and nothing covers it',
    (tester) async {
      await _boot(tester);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final presence = tester.getRect(
        find.byKey(const ValueKey('home-presence')),
      );
      final headline = tester.getRect(
        find.byKey(const ValueKey('home-headline')),
      );
      final start = tester.getRect(
        find.byKey(const ValueKey('start-practice')),
      );

      // The spacer reserves the presence box below the bar; the box itself starts 16 dp higher.
      expect(presence.height + 16, greaterThanOrEqualTo(screen.height * 0.45));
      expect(headline.top, greaterThanOrEqualTo(presence.bottom));
      expect(start.bottom, lessThanOrEqualTo(screen.height));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the profile control opens the profile', (tester) async {
    await _boot(tester);
    await tester.tap(
      find.byWidgetPredicate((w) => w is IconAction && w.label == 'Profile'),
    );
    await _settle(tester);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('profile and history are separate outer pages', (tester) async {
    await _boot(tester);
    await tester.scrollUntilVisible(
      find.text('History'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await _settle(tester);
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await _settle(tester);
    expect(find.byType(ProfileScreen), findsNothing);

    await tester.scrollUntilVisible(
      find.text('History'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('History'));
    await _settle(tester);
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('Past practices on this phone.'), findsOneWidget);
    expect(find.text('No practices yet.'), findsOneWidget);
  });

  testWidgets('an upcoming interview date shows as one quiet line', (
    tester,
  ) async {
    final soon = DateTime.now().add(const Duration(days: 5));
    await _boot(
      tester,
      services: _services(
        profile: Profile(interviewDate: soon, targetRole: 'barista'),
      ),
    );
    expect(find.text('Interview in 5 days · barista'), findsOneWidget);
  });

  testWidgets('no overflow with large text or on a small phone', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _boot(tester);
    expect(tester.takeException(), isNull);
    await _boot(tester, physical: const Size(720, 1280), ratio: 2);
    await _settle(tester, 200);
    expect(tester.takeException(), isNull);
  });

  test('presence size follows the screen', () {
    final phone = homePresenceSize(const Size(411, 891), EdgeInsets.zero);
    expect(phone, greaterThan(411));
    expect(phone / 891, greaterThanOrEqualTo(0.5));
    expect(
      homePresenceSize(const Size(360, 640), EdgeInsets.zero),
      lessThanOrEqualTo(640 * 0.55),
    );
    expect(homePresenceSize(const Size(1024, 1366), EdgeInsets.zero), 640);
  });

  testWidgets('home explains the practice without a glass card', (
    tester,
  ) async {
    await _boot(tester);
    expect(find.text('Tell me the job.'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Typing'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.byType(FrostedPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('history line counts practices on this phone', () {
    expect(homeHistoryLine(0), 'No practices yet');
    expect(homeHistoryLine(1), '1 practice');
    expect(homeHistoryLine(3), '3 practices');
  });

  test('profile line names only what was saved', () {
    expect(homeProfileLine(const Profile()), 'Saved on this phone');
    expect(homeProfileLine(const Profile(name: 'Alex')), 'Alex');
    expect(homeProfileLine(const Profile(targetRole: 'barista')), 'barista');
    expect(
      homeProfileLine(const Profile(name: 'Alex', targetRole: 'barista')),
      'Alex · barista',
    );
  });

  test('interview countdown wording', () {
    final now = DateTime(2026, 9, 25, 21);
    expect(interviewCountdown(const Profile(), now), isNull);
    expect(
      interviewCountdown(Profile(interviewDate: DateTime(2026, 9, 24)), now),
      isNull,
    );
    expect(
      interviewCountdown(Profile(interviewDate: DateTime(2026, 9, 25)), now),
      'Interview today',
    );
    expect(
      interviewCountdown(Profile(interviewDate: DateTime(2026, 9, 26)), now),
      'Interview tomorrow',
    );
    expect(
      interviewCountdown(
        Profile(
          interviewDate: DateTime(2026, 10, 2),
          targetRole: 'junior analyst',
        ),
        now,
      ),
      'Interview in 7 days · junior analyst',
    );
  });
}
