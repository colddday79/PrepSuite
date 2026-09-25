import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/app.dart';
import 'package:prepsuite/design/components.dart';
import 'package:prepsuite/design/icons.dart';
import 'package:prepsuite/design/tokens.dart';

/// WCAG 2.x relative luminance and contrast ratio.
double _luminance(Color c) {
  double channel(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final x = _luminance(a);
  final y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

bool _fontLoaded = false;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
  bool reduceMotion = false,
  Size size = const Size(411, 891),
}) async {
  if (!_fontLoaded) {
    // Real Mona Sans metrics, so size and overflow checks match the device.
    await tester.runAsync(() async {
      final loader = FontLoader('MonaSans')..addFont(rootBundle.load('assets/fonts/MonaSans.ttf'));
      await loader.load();
    });
    _fontLoaded = true;
  }
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: prepTheme(),
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: reduceMotion),
      child: page!,
    ),
    home: Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(Space.gutter), child: Center(child: child)),
      ),
    ),
  ));
}

Finder _in<T>(Finder of) => find.descendant(of: of, matching: find.byType(T));

Color? _fill(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(_in<DecoratedBox>(find.byType(PrimaryButton)).first);
  final decoration = box.decoration as ShapeDecoration;
  expect(decoration.gradient, isNull, reason: 'the primary button is a solid fill');
  return decoration.color;
}

double _scale(WidgetTester tester) => tester.widget<AnimatedScale>(_in<AnimatedScale>(find.byType(PrimaryButton))).scale;

Color? _labelColor(WidgetTester tester, String label) => tester.widget<Text>(find.text(label)).style?.color;

void main() {
  group('contrast', () {
    const surfaces = {'bg': PrepColors.bg, 'surface1': PrepColors.surface1, 'surface2': PrepColors.surface2};
    const texts = {
      'text': PrepColors.text,
      'text2': PrepColors.text2,
      'text3': PrepColors.text3,
      'accent': PrepColors.accent,
      'danger': PrepColors.danger,
    };

    for (final t in texts.entries) {
      for (final s in surfaces.entries) {
        test('${t.key} on ${s.key} is at least 4.5:1', () {
          expect(contrast(t.value, s.value), greaterThanOrEqualTo(4.5));
        });
      }
    }

    test('button labels, selection and focus', () {
      expect(contrast(PrepColors.bg, PrepColors.text), greaterThanOrEqualTo(4.5)); // primary label
      expect(contrast(PrepColors.bg, const Color(0xFFDED8D0)), greaterThanOrEqualTo(4.5)); // pressed
      expect(contrast(PrepColors.text3, PrepColors.surface2), greaterThanOrEqualTo(4.5)); // disabled
      expect(contrast(PrepColors.bg, PrepColors.accent), greaterThanOrEqualTo(4.5)); // selected day
      // Non-text: focus ring and the outline of unselected controls need 3:1.
      for (final s in surfaces.values) {
        expect(contrast(PrepColors.focus, s), greaterThanOrEqualTo(3));
        expect(contrast(PrepColors.text3, s), greaterThanOrEqualTo(3));
      }
    });

    test('the WCAG function matches known values', () {
      expect(contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 0.01));
      expect(contrast(const Color(0xFF777777), const Color(0xFFFFFFFF)), closeTo(4.48, 0.01));
    });
  });

  group('PrimaryButton', () {
    testWidgets('enabled: solid light fill, dark label, 56 dp', (tester) async {
      await _pump(tester, PrimaryButton('Start practice', onPressed: () {}));
      expect(_fill(tester), PrepColors.text);
      expect(_labelColor(tester, 'Start practice'), PrepColors.bg);
      expect(tester.getSize(find.byType(PrimaryButton)).height, greaterThanOrEqualTo(56));
      expect(_scale(tester), 1);
    });

    testWidgets('disabled: dark slab with a readable label, taps do nothing', (tester) async {
      await _pump(tester, const PrimaryButton('Use this', onPressed: null));
      expect(_fill(tester), PrepColors.surface2);
      expect(_labelColor(tester, 'Use this'), PrepColors.text3);
      await tester.tap(find.text('Use this'));
      await tester.pump(Motion.press);
      expect(_scale(tester), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pressed: darker fill and 0.98 scale, released on lift', (tester) async {
      var taps = 0;
      await _pump(tester, PrimaryButton('Next question', onPressed: () => taps++));
      final gesture = await tester.startGesture(tester.getCenter(find.byType(PrimaryButton)));
      await tester.pump();
      await tester.pump(Motion.press);
      expect(_scale(tester), Motion.pressScale);
      expect(_fill(tester), const Color(0xFFDED8D0));

      await gesture.up();
      await tester.pump();
      await tester.pump(Motion.fade);
      expect(_scale(tester), 1);
      expect(_fill(tester), PrepColors.text);
      expect(taps, 1);
    });

    testWidgets('reduced motion keeps the darken but skips the scale', (tester) async {
      await _pump(tester, PrimaryButton('Next question', onPressed: () {}), reduceMotion: true);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(PrimaryButton)));
      await tester.pump();
      await tester.pump(Motion.press);
      expect(_scale(tester), 1);
      expect(_fill(tester), isNot(PrepColors.text));
      await gesture.up();
    });

    testWidgets('busy shows a spinner, keeps the label and ignores taps', (tester) async {
      var taps = 0;
      await _pump(tester, PrimaryButton('Saving', busy: true, onPressed: () => taps++));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Saving'), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('semantics: a button that says whether it can be used', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, Column(mainAxisSize: MainAxisSize.min, children: [
        PrimaryButton('Start practice', onPressed: () {}),
        const PrimaryButton('Use this', onPressed: null),
      ]));
      expect(
        tester.getSemantics(find.byType(PrimaryButton).first),
        isSemantics(label: 'Start practice', isButton: true, hasEnabledState: true, isEnabled: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byType(PrimaryButton).last),
        isSemantics(label: 'Use this', isButton: true, hasEnabledState: true, isEnabled: false, hasTapAction: false),
      );
      handle.dispose();
    });
  });

  group('shared components', () {
    Widget sampler(TextEditingController controller) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CoachTopBar(onClose: () {}, status: 'Question 1 of 5 · Graduate civil engineer designing bridges'),
              PrimaryButton('See your notes', icon: PrepIcons.check, onPressed: () {}),
              const SizedBox(height: Space.s),
              Wrap(alignment: WrapAlignment.center, spacing: Space.s, children: [
                const QuietButton('Hear it again', icon: PrepIcons.replay, onPressed: null),
                QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: () {}),
                QuietButton('OK', onPressed: () {}),
              ]),
              LinkRow(
                icon: PrepIcons.keyboard,
                title: 'Practise by typing',
                meta: "Answer in writing when you can't talk out loud.",
                onTap: () {},
              ),
              const Hairline(indent: Space.gutter),
              Align(
                alignment: Alignment.centerLeft,
                child: IconAction(PrepIcons.user, label: 'Profile', plain: true, onPressed: () {}),
              ),
              PrepTextField(
                controller: controller,
                hint: 'For example: barista at a busy café',
                label: 'Target role',
                errorText: 'Add a few words about the job.',
              ),
            ],
          ),
        );

    testWidgets('every control is at least 48 by 48 dp and labelled', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(tester, sampler(controller));

      final ok = tester.getSize(find.widgetWithText(QuietButton, 'OK'));
      expect(ok.width, greaterThanOrEqualTo(48));
      expect(ok.height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.widgetWithText(QuietButton, 'Type instead')).height, greaterThanOrEqualTo(48));
      for (final icon in tester.widgetList(find.byType(IconAction))) {
        expect(tester.getSize(find.byWidget(icon)), const Size(48, 48));
      }
      expect(tester.getSize(find.byType(LinkRow)).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byType(TextField)).height, greaterThanOrEqualTo(48));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('semantics: icon controls can be activated, rows read as one button', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(tester, sampler(controller));

      expect(
        tester.getSemantics(find.byWidgetPredicate((w) => w is IconAction && w.label == 'Close')),
        isSemantics(label: 'Close', isButton: true, hasTapAction: true),
      );
      final row = tester.getSemantics(find.byType(LinkRow));
      expect(row.label, contains('Practise by typing'));
      expect(row.label, contains('Answer in writing'));
      expect(row, isSemantics(isButton: true, hasTapAction: true));
      expect(
        tester.getSemantics(find.widgetWithText(QuietButton, 'Hear it again')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      expect(
        tester.getSemantics(find.widgetWithText(QuietButton, 'Type instead')),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('a gold focus ring appears for keyboard focus only', (tester) async {
      await _pump(tester, Column(mainAxisSize: MainAxisSize.min, children: [
        PrimaryButton('Start practice', onPressed: () {}),
        QuietButton('Type instead', onPressed: () {}),
      ]));
      bool ring(Finder control) => tester
          .widget<CustomPaint>(find.descendant(of: find.descendant(of: control, matching: find.byType(FocusRing)), matching: find.byType(CustomPaint)).first)
          .foregroundPainter != null;

      await tester.tap(find.text('Start practice'));
      await tester.pump(Motion.fade);
      expect(ring(find.byType(PrimaryButton)), isFalse, reason: 'touch never shows the ring');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final primary = ring(find.byType(PrimaryButton));
      final quiet = ring(find.byType(QuietButton));
      expect(primary || quiet, isTrue);
      expect(primary && quiet, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(find.byType(PrimaryButton)), !primary);
      expect(ring(find.byType(QuietButton)), !quiet);
    });

    testWidgets('no overflow at 1.3x text on a small phone', (tester) async {
      final controller = TextEditingController(text: 'Graduate civil engineer');
      addTearDown(controller.dispose);
      await _pump(tester, sampler(controller), textScale: 1.3, size: const Size(320, 640));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('prepTheme', () {
    testWidgets('every text role is Mona Sans with an explicit weight axis', (tester) async {
      final theme = prepTheme().textTheme;
      final roles = [
        theme.displayLarge, theme.displayMedium, theme.displaySmall,
        theme.headlineLarge, theme.headlineMedium, theme.headlineSmall,
        theme.titleLarge, theme.titleMedium, theme.titleSmall,
        theme.bodyLarge, theme.bodyMedium, theme.bodySmall,
        theme.labelLarge, theme.labelMedium, theme.labelSmall,
      ];
      for (final style in roles) {
        expect(style?.fontFamily, 'MonaSans');
        expect(style?.fontVariations?.any((v) => v.axis == 'wght' && v.value >= 400), isTrue);
      }
    });

    testWidgets('the date picker looks like the app', (tester) async {
      await _pump(tester, Builder(
        builder: (context) => PrimaryButton('Pick a date', onPressed: () => showDatePicker(
          context: context,
          initialDate: DateTime(2026, 9, 25),
          currentDate: DateTime(2026, 9, 25),
          firstDate: DateTime(2026, 9, 10),
          lastDate: DateTime(2027, 9, 25),
        )),
      ));
      await tester.tap(find.text('Pick a date'));
      await tester.pumpAndSettle();

      final dialog = find.byType(Dialog);
      expect(tester.widget<Material>(_in<Material>(dialog).first).color, PrepColors.surface2);
      final day = tester.widget<Text>(find.text('14')).style!;
      expect(day.fontFamily, 'MonaSans');
      expect(day.color, PrepColors.text);
      expect(tester.widget<Text>(find.text('25')).style!.color, PrepColors.bg); // selected, on gold
      expect(tester.widget<Text>(find.text('5')).style!.color!.a, lessThan(1)); // before firstDate
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
    });

    testWidgets('dialogs, sheets and snack bars use the palette', (tester) async {
      await _pump(tester, Builder(
        builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
          QuietButton('Dialog', onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(title: Text('Delete this practice?'), content: Text('This removes it.')),
          )),
          QuietButton('Sheet', onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox(height: 120))),
          QuietButton('Snack', onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved practice deleted.')))),
        ]),
      ));

      await tester.tap(find.text('Dialog'));
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(_in<Material>(find.byType(AlertDialog)).first).color, PrepColors.surface2);
      final title = tester.widget<RichText>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(RichText)).first);
      expect(title.text.style?.fontFamily, 'MonaSans');
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sheet'));
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(_in<Material>(find.byType(BottomSheet)).first).color, PrepColors.surface1);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Snack'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<Material>(_in<Material>(find.byType(SnackBar)).first).color, PrepColors.surface2);
    });

    testWidgets('switches, radios and checkboxes: gold when on, readable outline when off', (tester) async {
      await _pump(tester, Column(mainAxisSize: MainAxisSize.min, children: [
        Switch(value: true, onChanged: (_) {}),
        Switch(value: false, onChanged: (_) {}),
        RadioGroup<int>(groupValue: 1, onChanged: (_) {}, child: const Row(children: [Radio(value: 1), Radio(value: 2)])),
        Checkbox(value: true, onChanged: (_) {}),
      ]));
      final theme = prepTheme();
      expect(theme.switchTheme.trackColor!.resolve({WidgetState.selected}), PrepColors.accent);
      expect(theme.switchTheme.trackOutlineColor!.resolve({}), PrepColors.text3);
      expect(theme.radioTheme.fillColor!.resolve({WidgetState.selected}), PrepColors.accent);
      expect(theme.radioTheme.fillColor!.resolve({}), PrepColors.text3);
      expect(theme.checkboxTheme.fillColor!.resolve({WidgetState.selected}), PrepColors.accent);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      expect(tester.takeException(), isNull);
    });
  });
}
