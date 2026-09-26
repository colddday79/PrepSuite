import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// A warm near-black room lit by the gold presence, with gold as the one accent.
///
/// WCAG contrast of every text colour (asserted in test/design_test.dart):
///
/// |           | bg    | surface1 | surface2 |
/// |-----------|-------|----------|----------|
/// | text      | 17.1  | 16.1     | 14.7     |
/// | text2     |  9.4  |  8.9     |  8.1     |
/// | text3     |  6.2  |  5.8     |  5.3     |
/// | accent    | 10.2  |  9.6     |  8.8     |
/// | danger    |  8.6  |  8.1     |  7.4     |
///
/// [bg] on [text] (the primary button label) is 17.1:1 and [bg] on [accent] is 10.2:1.
/// Hairlines are decorative: [line] is 1.4:1 on bg, [lineStrong] 1.9:1. Controls whose outline is
/// their only boundary (checkbox, radio, switch) use [text3] instead, which clears 3:1 everywhere.
abstract final class PrepColors {
  static const bg = Color(0xFF0E0C0A);
  static const surface1 = Color(0xFF171410);
  static const surface2 = Color(0xFF211D18);
  static const line = Color(0xFF302A24);
  static const lineStrong = Color(0xFF463E35);
  static const text = Color(0xFFF5EFE6);
  static const text2 = Color(0xFFBDB3A5);
  static const text3 = Color(0xFF9A8F81);
  static const accent = Color(0xFFE6B35E);
  static const accentTint = Color(0xFF2B2114);
  static const danger = Color(0xFFF2937F);
  static const recording = Color(0xFFF0725E);
  static const glassBorder = Color(0x1FFFFFFF);
  static const glassBg = Color(0x801C1814);
  static const cardHighlight = Color(0x2EFFF4E0);

  /// Warm mid-grey press tint. It reads on the light primary fill and on the dark surfaces alike.
  static const press = Color(0xFF8C8276);

  /// Keyboard, D-pad and switch-access focus ring.
  static const focus = accent;

  /// Behind dialogs and sheets.
  static const scrim = Color(0xB3000000);
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

/// Bodoni Moda for what the coach says (headlines, questions, the wordmark), Jost for everything
/// you read or tap. The "Luxury Minimalist" pairing from the UI UX Pro Max typography data, chosen
/// for the gold-on-black palette. Both are variable fonts under the SIL Open Font License 1.1.
abstract final class PrepFonts {
  static const display = 'BodoniModa';
  static const text = 'Jost';
}

FontWeight _weight(double weight) => FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)];

TextStyle _bodoni(double size, double height, double weight, {double tracking = 0, Color color = PrepColors.text}) {
  return TextStyle(
    fontFamily: PrepFonts.display,
    fontSize: size,
    height: height / size,
    // Tracking is in em; Flutter wants logical pixels.
    letterSpacing: tracking * size,
    fontWeight: _weight(weight),
    // The optical-size axis is tuned for print. On a phone the display cuts' hairlines all but
    // vanish ("the" reads "thc"), so the axis runs at about half the point size, capped at 18.
    fontVariations: [FontVariation.weight(weight), FontVariation('opsz', (size * 0.55).clamp(6, 18).toDouble())],
    color: color,
  );
}

TextStyle _jost(
  double size,
  double height,
  double weight, {
  double tracking = 0,
  Color color = PrepColors.text,
  List<FontFeature>? features,
}) {
  return TextStyle(
    fontFamily: PrepFonts.text,
    fontSize: size,
    height: height / size,
    letterSpacing: tracking * size,
    fontWeight: _weight(weight),
    // A variable font's default instance isn't the weight asked for, so every style sets the axis.
    fontVariations: [FontVariation.weight(weight)],
    fontFeatures: features,
    color: color,
  );
}

/// Jost's x-height is lower than Mona Sans', so text sizes sit one step above the old scale.
abstract final class PrepType {
  /// The one big line on Home, under the presence.
  static final display = _bodoni(32, 37, 500, tracking: -0.01);
  static final question = _bodoni(26, 33, 500, tracking: -0.005);
  static final questionM = _bodoni(21, 28, 500);
  static final headline = _bodoni(29, 35, 600, tracking: -0.01);
  static final wordmark = _bodoni(23, 28, 600, tracking: -0.01);

  /// Dialog and sheet titles, a step above [titleM].
  static final titleL = _jost(22, 28, 500);
  static final quote = _jost(17, 26, 400);
  static final titleM = _jost(18, 24, 500);
  static final bodyL = _jost(17, 25, 400);
  static final bodyLMedium = _jost(17, 25, 500);
  static final body = _jost(16, 24, 400, color: PrepColors.text2);

  /// The primary button label.
  static final button = _jost(17, 22, 500, tracking: 0.005);
  static final label = _jost(15, 20, 500, tracking: 0.01);
  static final meta = _jost(14, 19, 400, tracking: 0.01, color: PrepColors.text2);

  /// Small print (helper and legal lines). Never below 12.
  static final caption = _jost(13, 17, 400, tracking: 0.02, color: PrepColors.text3);
  static final timer = _jost(22, 26, 400, features: const [FontFeature.tabularFigures()]);
}
