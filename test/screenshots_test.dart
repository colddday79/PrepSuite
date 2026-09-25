// Renders Home and the start of a practice to PNG files for design review, with the real fonts and the presence's
// poster frame. Skipped in the normal test run; to make them:
//
//   flutter test test/screenshots_test.dart --dart-define=SCREENSHOTS=true
//
// The files land in build/screenshots/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/app/services.dart';
import 'package:prepsuite/app/session.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/fakes.dart';
import 'package:prepsuite/design/hologram.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

class _Phone {
  const _Phone(this.name, this.size, this.ratio, {this.top = 32});

  final String name;
  final Size size;
  final double ratio;
  final double top;
  final double bottom = 16;
}

const _phones = [
  _Phone('pixel', Size(1080, 2400), 2.625),
  _Phone('galaxy_s26', Size(1080, 2340), 2.8125),
  _Phone('small', Size(720, 1560), 2.0, top: 24),
];

void main() {
  final frame = GlobalKey();

  Future<void> boot(WidgetTester tester, _Phone phone, AppServices services) async {
    HologramVideo.instance.enabled = false;
    await tester.runAsync(() async {
      await (FontLoader('BodoniModa')..addFont(rootBundle.load('assets/fonts/BodoniModa.ttf'))).load();
      await (FontLoader('Jost')..addFont(rootBundle.load('assets/fonts/Jost.ttf'))).load();
    });
    tester.view.physicalSize = phone.size;
    tester.view.devicePixelRatio = phone.ratio;
    tester.view.padding = FakeViewPadding(top: phone.top * phone.ratio, bottom: phone.bottom * phone.ratio);
    tester.view.viewPadding = FakeViewPadding(top: phone.top * phone.ratio, bottom: phone.bottom * phone.ratio);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(key: frame, child: PrepSuiteApp(services: services)));
    await tester.runAsync(() => precacheImage(const AssetImage(HologramVideo.poster), frame.currentContext!));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      final boundary = frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/screenshots/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> settle(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  AppServices services({bool consented = true}) => AppServices(
        coach: FakeCoachApi(latency: const Duration(seconds: 3)),
        speech: FakeSpeechCapture(),
        voice: FakeInterviewerVoice(),
        consent: MemoryConsentStore(value: consented),
        mic: GrantedMicPermission(),
        sessions: SessionStore(),
        coachLabel: 'screenshots',
        speechLabel: 'screenshots',
      );

  for (final phone in _phones) {
    testWidgets('home on ${phone.name}', (tester) async {
      await boot(tester, phone, services());
      await shoot(tester, '${phone.name}_1_home');

      await tester.ensureVisible(find.text('Start practice'));
      await tester.tap(find.text('Start practice'));
      await settle(tester, 1600);
      await shoot(tester, '${phone.name}_2_asking');

      await tester.tap(find.byKey(const ValueKey('record-button')));
      await settle(tester, 3400);
      await shoot(tester, '${phone.name}_3_listening');

      await tester.tap(find.byKey(const ValueKey('record-button')));
      await settle(tester, 600);
      await shoot(tester, '${phone.name}_4_check');

      await tester.tap(find.text('Use this'));
      await settle(tester, 900);
      await shoot(tester, '${phone.name}_5_writing_questions');

      await settle(tester, 3000);
      await settle(tester, 2500);
      await shoot(tester, '${phone.name}_6_first_question');
    }, skip: !_enabled);
  }

  // The hardest fits: the smallest phone with double text, split screen, and a tablet.
  for (final (name, size, ratio, scale) in const [
    ('stress_se_text2x', Size(640, 1136), 2.0, 2.0),
    ('stress_split_screen', Size(1082, 1181), 2.625, 1.0),
    ('stress_tablet_landscape', Size(2732, 2048), 2.0, 1.0),
  ]) {
    testWidgets('home, $name', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await boot(tester, _Phone(name, size, ratio, top: 20), services());
      await shoot(tester, '${name}_1_home');
      // Short windows scroll, so each control is brought into view before it is tapped.
      Future<void> tapInView(Finder finder, int ms) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await settle(tester, ms);
      }

      await tapInView(find.text('Start practice'), 1600);
      await tapInView(find.byKey(const ValueKey('record-button')), 1500);
      await tapInView(find.byKey(const ValueKey('record-button')), 600);
      await shoot(tester, '${name}_2_check');
      await tapInView(find.text('Use this'), 6000);
      await shoot(tester, '${name}_3_question');
    }, skip: !_enabled);
  }

  testWidgets('first run consent over Home', (tester) async {
    await boot(tester, _phones.first, services(consented: false));
    await settle(tester, 800);
    await shoot(tester, 'pixel_0_consent');
  }, skip: !_enabled);

  testWidgets('typing the job with the keyboard up', (tester) async {
    const phone = Size(1080, 2400);
    await boot(tester, _phones.first, services());
    await tester.ensureVisible(find.text('Practise by typing'));
    await tester.tap(find.text('Practise by typing'));
    await settle(tester, 600);
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * 2.625);
    tester.view.padding = FakeViewPadding(top: 32 * 2.625);
    await settle(tester, 600);
    await tester.enterText(find.byKey(const ValueKey('job-field')), 'Junior web developer, technical interview');
    await settle(tester, 400);
    expect(tester.view.physicalSize, phone);
    await shoot(tester, 'pixel_6_typing_keyboard');
  }, skip: !_enabled);
}
