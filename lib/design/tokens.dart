import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// A neutral graphite near-black (no blue cast, no gradients) and one accent: the colour of the
/// coach the person chose. The accent is spent sparingly: the one primary action, progress and
/// selection. Everything else is greys, so the screen reads as a calm product, not a glowing demo.
///
/// WCAG contrast of every text colour (asserted in test/design_test.dart):
///
/// |           | bg    | surface1 | surface2 |
/// |-----------|-------|----------|----------|
/// | text      | 17.8  | 16.3     | 14.8     |
/// | text2     | 10.0  |  9.1     |  8.3     |
/// | text3     |  6.4  |  5.8     |  5.3     |
/// | danger    |  8.5  |  7.8     |  7.0     |
///
/// Every assistant accent clears 7:1 on bg, and [bg] text on an accent fill (the primary button)
/// clears 7:1 too. Hairlines are decorative; controls whose outline is their only boundary use
/// [text3], which clears 3:1 everywhere.
abstract final class PrepColors {
  static const bg = Color(0xFF0C0D10);
  static const surface1 = Color(0xFF16181C);
  static const surface2 = Color(0xFF1F2126);
  static const line = Color(0xFF2A2D33);
  static const lineStrong = Color(0xFF3A3E45);
  static const text = Color(0xFFF4F5F7);
  static const text2 = Color(0xFFB6BAC2);
  static const text3 = Color(0xFF8F949D);
  static const danger = Color(0xFFFF8A7A);
  static const recording = Color(0xFFFF6B5B);
  static const glassBorder = Color(0x1FFFFFFF);
  static const glassBg = Color(0x8016181C);
  static const cardHighlight = Color(0x24FFFFFF);

  /// Neutral mid-grey press tint. It reads on the accent fill and on the dark surfaces alike.
  static const press = Color(0xFF80858F);

  /// Correct and not-quite states in drills. Words and icons always carry the meaning too.
  static const success = Color(0xFF7FD3A1);
  static const successTint = Color(0xFF15231B);
  static const warning = Color(0xFFF2B36B);
  static const warningTint = Color(0xFF2A2015);

  /// Behind dialogs and sheets.
  static const scrim = Color(0xB3000000);

  static Color _accent = const Color(0xFF45D0FF);

  /// The chosen assistant's colour: buttons, selection, focus and progress.
  static Color get accent => _accent;

  /// The accent at low strength over [bg], for tinted discs and selected rows.
  static Color get accentTint => Color.alphaBlend(_accent.withValues(alpha: 0.16), bg);

  /// Keyboard, D-pad and switch-access focus ring.
  static Color get focus => _accent;

  /// Switches the accent to [colour]; the app root rebuilds everything after calling it.
  static void useAccent(Color colour) => _accent = colour;
}

/// 4/8 spacing scale.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3 = 32;
  static const double x4 = 40;
  static const double x5 = 48;
  static const double gutter = 20;
}

abstract final class Radii {
  static const double chip = 12;
  static const double control = 16;
  static const double card = 24;
  static const double sheet = 28;
}

abstract final class Motion {
  static const decelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const standard = Cubic(0.2, 0, 0, 1);

  /// Press-in: feedback lands inside one tap.
  static const press = Duration(milliseconds: 100);
  static const fade = Duration(milliseconds: 200);
  static const enter = Duration(milliseconds: 300);

  /// How far a pressed button settles. Skipped when the system asks for less motion.
  static const double pressScale = 0.98;
}

const String _family = 'MonaSans';

TextStyle _mona(
  double size,
  double height,
  double weight, {
  double tracking = 0,
  double width = 100,
  Color color = PrepColors.text,
  List<FontFeature>? features,
}) {
  return TextStyle(
    fontFamily: _family,
    fontSize: size,
    height: height / size,
    // Tracking in the native tokens is in em; Flutter wants logical pixels.
    letterSpacing: tracking * size,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
    // The variable font's default weight is 200, so every style sets the axis explicitly.
    fontVariations: [FontVariation.weight(weight), FontVariation.width(width)],
    fontFeatures: features,
    color: color,
  );
}

/// Mona Sans only. Weight carries the hierarchy (600 display and titles, 500 emphasis, 400 body);
/// the width axis narrows only the brand-scale lines (wordmark, display) and the timer digits.
abstract final class PrepType {
  /// The one big line on Home, under the presence.
  static final display = _mona(30, 36, 600, tracking: -0.025, width: 96);
  static final question = _mona(25, 34, 500, tracking: -0.02);
  static final questionM = _mona(20, 28, 500, tracking: -0.01);
  static final headline = _mona(28, 35, 650, tracking: -0.02);

  /// Dialog and sheet titles, a step above [titleM].
  static final titleL = _mona(21, 27, 600, tracking: -0.015);
  static final quote = _mona(16, 25, 400, tracking: 0.005);
  static final titleM = _mona(17, 23, 600, tracking: -0.01);
  static final bodyL = _mona(16, 24, 400);
  static final bodyLMedium = _mona(16, 24, 500);
  static final body = _mona(15, 23, 400, tracking: 0.005, color: PrepColors.text2);

  /// The primary button label.
  static final button = _mona(16, 20, 600, tracking: -0.005);
  static final label = _mona(14, 20, 600, tracking: 0.01);
  static final meta = _mona(13, 18, 500, tracking: 0.01, color: PrepColors.text2);

  /// Small print (helper and legal lines). Never below 12.
  static final caption = _mona(12, 16, 500, tracking: 0.02, color: PrepColors.text3);
  static final timer = _mona(22, 26, 400, width: 88, features: const [FontFeature.tabularFigures()]);
  static final wordmark = _mona(18, 23, 700, tracking: -0.015, width: 92);
}
