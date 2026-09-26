// Every screen on every kind of phone: walks Home, settings, the profile, a whole practice (with
// asking the coach and the notes read aloud) and practice history on small, standard and large
// phones, a foldable, split screen and tablets, at normal and double text size, with safe-area
// insets and the keyboard, and fails on any layout error (the "overflowed by N pixels" stripes).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/profile.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/app/session.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/design/components.dart';
import 'package:prepsuite/design/hologram.dart';

class _Device {
  const _Device(this.name, this.width, this.height, this.ratio, {this.top = 24, this.bottom = 16});

  final String name;
  final double width;
  final double height;
  final double ratio;
  final double top;
  final double bottom;
}

const _devices = [
  _Device('iPhone SE (1st gen) 320x568', 320, 568, 2, top: 20, bottom: 0),
  _Device('small Android 360x640', 360, 640, 3),
  _Device('iPhone SE 375x667', 375, 667, 2, top: 20, bottom: 0),
  _Device('Android 360x780', 360, 780, 3),
  _Device('iPhone 15 390x844', 390, 844, 3, top: 47, bottom: 34),
  _Device('Galaxy S26 384x832', 384, 832, 2.8125, top: 32),
  _Device('Pixel 412x915', 412, 915, 2.625, top: 32),
  _Device('Pro Max 430x932', 430, 932, 3, top: 59, bottom: 34),
  _Device('split screen 412x450', 412, 450, 2.625, top: 0),
  _Device('foldable open 673x841', 673, 841, 2.625),
  _Device('tablet 768x1024', 768, 1024, 2),
  _Device('tablet landscape 1366x1024', 1366, 1024, 2, top: 24, bottom: 20),
];

void main() {
  for (final device in _devices) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('${device.name}, text x$scale: every screen lays out cleanly', (tester) async {
        await _walkEverything(tester, device, scale);
      });
    }
  }
}

Future<void> _walkEverything(WidgetTester tester, _Device device, double scale) async {
  HologramVideo.instance.enabled = false;
  await tester.runAsync(() async {
    await (FontLoader('BodoniModa')..addFont(rootBundle.load('assets/fonts/BodoniModa.ttf'))).load();
    await (FontLoader('Jost')..addFont(rootBundle.load('assets/fonts/Jost.ttf'))).load();
  });
  tester.view.physicalSize = Size(device.width * device.ratio, device.height * device.ratio);
  tester.view.devicePixelRatio = device.ratio;
  final insets = FakeViewPadding(top: device.top * device.ratio, bottom: device.bottom * device.ratio);
  tester.view.padding = insets;
  tester.view.viewPadding = insets;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  final services = AppServices(
    // The first request fails, so the error screens are walked too.
    coach: FakeCoachApi(latency: const Duration(milliseconds: 200), failuresBeforeSuccess: 1),
    speech: FakeSpeechCapture(),
    voice: FakeInterviewerVoice(),
    consent: MemoryConsentStore(),
    mic: GrantedMicPermission(),
    sessions: SessionStore(),
    // A date and a role, so Home shows its countdown line.
    profile: ProfileStore(initial: Profile(interviewDate: DateTime.now().add(const Duration(days: 5)), targetRole: 'Junior barista')),
    coachLabel: 'layout',
    speechLabel: 'layout',
  );
  await tester.pumpWidget(PrepSuiteApp(services: services));

  Future<void> settle([int ms = 600]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Each step must lay out without an error, and no text may be cut off by a box too small for
  // it (that raises no error, the words just disappear). The message names where it broke.
  Future<void> clean(String where) async {
    await settle(100);
    final at = '$where on ${device.name} at text x${tester.platformDispatcher.textScaleFactor}';
    expect(tester.takeException(), isNull, reason: at);
    for (final element in find.byType(RichText).evaluate()) {
      final text = element.renderObject! as RenderParagraph;
      if (!text.hasSize || text.size.width == 0) continue;
      final needed = text.getMaxIntrinsicHeight(text.size.width);
      expect(needed, lessThanOrEqualTo(text.size.height + 0.5), reason: 'text cut off, "${text.text.toPlainText()}": $at');
    }
  }

  Future<void> tap(Finder finder, [int ms = 600]) async {
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await settle(ms);
  }

  Future<void> keyboard(bool up) async {
    tester.view.viewInsets = FakeViewPadding(bottom: up ? device.height * 0.4 * device.ratio : 0);
    await settle(300);
  }

  final record = find.byKey(const ValueKey('record-button'));
  Finder action(String label) => find.byWidgetPredicate((w) => w is IconAction && w.label == label);

  // First run: the consent sheet over Home.
  await settle(900);
  await clean('consent sheet');
  await tap(find.text('Accept'));
  await clean('Home');

  // Settings sheet.
  await tap(action('Settings'));
  await clean('settings sheet');
  await tester.binding.handlePopRoute();
  await settle();

  // Profile: typing a detail with the keyboard up, the date picker and the delete dialog.
  await tap(action('Profile'));
  await clean('profile');
  await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Sam');
  await keyboard(true);
  await clean('profile with the keyboard up');
  await keyboard(false);
  await tap(find.byKey(const ValueKey('profile-date')));
  await clean('interview date picker');
  await tap(find.text('Cancel'));
  await tap(find.text('Delete everything on this phone'));
  await clean('delete everything dialog');
  await tap(find.text('Cancel'));
  await tester.binding.handlePopRoute();
  await settle();

  // Say the job: the interviewer asks, listening, then checking what was heard.
  await tap(find.text('Start practice'), 1600);
  await clean('intake, the interviewer asking');
  await tap(record, 1500);
  await clean('intake listening');
  await tap(record, 400);
  await clean('intake check');
  await keyboard(true);
  await clean('intake check with the keyboard up');
  await keyboard(false);

  // The coach fails once: the error, then questions.
  await tap(find.text('Use this'), 300);
  await clean('writing questions');
  await settle(400);
  await clean('questions error');
  await tap(find.text('Try again'), 1800);
  await clean('interview, question asked');

  // Question 1 out loud: recording, checking, feedback, then asking the coach by typing.
  await tap(record, 1200);
  await clean('interview recording');
  await tap(record, 400);
  await clean('interview check');
  await tap(find.text('Get feedback'), 800);
  await clean('feedback');
  await tap(action('Close'));
  await clean('end this practice dialog');
  await tap(find.text('Keep going'));
  await tap(find.text('Ask the coach'), 600);
  await clean('ask the coach');
  await tap(find.text('Type instead'), 300);
  await keyboard(true);
  await clean('typing a question for the coach, keyboard up');
  await tester.enterText(find.byKey(const ValueKey('ask-field')), 'How long should this answer be?');
  await keyboard(false);
  await tap(find.text('Send question'), 800);
  await clean("the coach's answer");
  await tap(find.text('Close'), 300);
  await tap(find.text('Next question'), 1800);

  // Questions 2 to 5 typed, with the keyboard up.
  for (var i = 2; i <= 5; i++) {
    await tap(find.text('Type instead'), 300);
    await keyboard(true);
    await clean('typing an answer, question $i');
    await tester.enterText(find.byKey(const ValueKey('answer-field')), 'I checked the ticket, remade the drink and told the customer what went wrong.');
    await keyboard(false);
    await tap(find.text('Send answer'), 800);
    await clean('typed feedback, question $i');
    await tap(find.text(i == 5 ? 'See your notes' : 'Next question'), 1800);
  }

  // The wrap-up notes, read aloud, then Home again.
  await settle(600);
  await clean('wrap-up');
  await tap(find.text('Hear your notes'), 300);
  await clean('wrap-up, reading the notes');
  await tap(find.text('Done'), 900);
  await clean('Home after a practice');
  await tap(action('Settings'));
  await tap(find.text('Delete saved practice'));
  await clean('delete saved practice dialog');
  await tap(find.text('Cancel'));
  await tester.binding.handlePopRoute();
  await settle();

  // Practice history in the profile.
  await tap(find.text('Profile and history'));
  await clean('profile with practice history');
  await tester.binding.handlePopRoute();
  await settle();

  // Typing the job instead, keyboard up.
  await tap(find.text('Practise by typing'), 600);
  await keyboard(true);
  await clean('typing the job');
  await keyboard(false);
}
