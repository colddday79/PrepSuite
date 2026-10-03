import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// A light, warm-paper app with bold black type and one coach colour, used two ways: [accent] (a
/// deep tone for progress, selection, focus and small labels) and [accentSoft] (a pale stage the
/// robot stands on). The main action is solid [ink]. No gradients, glows or glass.
///
/// WCAG contrast of every text colour (asserted in test/design_test.dart):
///
/// |           | bg    | surface1 | surface2 |
/// |-----------|-------|----------|----------|
/// | text      | 16.6  | 18.4     | 15.5     |
/// | text2     |  7.2  |  8.0     |  6.7     |
/// | text3     |  5.3  |  5.9     |  4.9     |
/// | danger    |  5.9  |  6.6     |  5.5     |
///
/// Every coach [accent] clears 4.5:1 on bg, surface2 and its own [accentSoft]; [bg] text on an
/// accent fill clears 4.5:1 too. Hairlines are decorative; controls whose outline is their only
/// boundary use [text3], which clears 3:1 everywhere.
abstract final class PrepColors {
  static const bg = Color(0xFFF5F3EE);
  static const surface1 = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFEEEBE4);
  static const line = Color(0xFFE3DED5);
  static const lineStrong = Color(0xFFCDC7BC);
  static const text = Color(0xFF141416);
  static const text2 = Color(0xFF4F5057);
  static const text3 = Color(0xFF63646B);

  /// The main action's fill: near-black, with [bg] text on it.
  static const ink = Color(0xFF141416);
  static const danger = Color(0xFFB42318);
  static const recording = Color(0xFFD92D20);
  static const glassBorder = Color(0x1F141416);
  static const glassBg = Color(0xCCFFFFFF);
  static const cardHighlight = Color(0x80FFFFFF);

  /// Press tint. It reads on the ink fill and on the light surfaces alike.
  static const press = Color(0xFF8A877F);

  /// Behind dialogs and sheets.
  static const scrim = Color(0x80141416);

  /// Correct and not-quite states in drills. Words and icons always carry the meaning too.
  static const success = Color(0xFF166F47);
  static const successTint = Color(0xFFE4F2EA);
  static const warning = Color(0xFF8C520A);
  static const warningTint = Color(0xFFFAEEDC);

  static Color _accent = const Color(0xFF2B5BBE);
  static Color _accentSoft = const Color(0xFFD8E4FB);

  /// The chosen coach's deep colour: progress, selection, focus and small labels.
  static Color get accent => _accent;

  /// The chosen coach's pale colour: the stage behind the robot and selected rows.
  static Color get accentSoft => _accentSoft;

  /// The accent at low strength over [bg], for tinted rows.
  static Color get accentTint => Color.alphaBlend(_accent.withValues(alpha: 0.1), bg);

  /// Keyboard, D-pad and switch-access focus ring.
  static Color get focus => _accent;

  /// Switches the coach colours; the app root rebuilds everything after calling it.
  static void useAccent(Color deep, [Color? soft]) {
    _accent = deep;
    _accentSoft = soft ?? Color.alphaBlend(deep.withValues(alpha: 0.18), const Color(0xFFFFFFFF));
  }
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

/// Mona Sans only, used for its width axis: headings are expanded (width 112–125) and heavy
/// (720–820) with tight tracking, so the app has a voice; body text stays normal width and
/// regular. The timer keeps tabular figures.
abstract final class PrepType {
  /// The one big line at the top of a tab ("Hi, Alex", "Practice").
  static final display = _mona(34, 38, 820, tracking: -0.035, width: 125);
  static final question = _mona(28, 33, 780, tracking: -0.025, width: 118);
  static final questionM = _mona(22, 27, 760, tracking: -0.02, width: 116);
  static final headline = _mona(28, 33, 800, tracking: -0.03, width: 122);

  /// Dialog, card and sheet titles, a step above [titleM].
  static final titleL = _mona(22, 27, 780, tracking: -0.02, width: 120);
  static final quote = _mona(16, 25, 430, tracking: 0.005);
  static final titleM = _mona(17, 22, 720, tracking: -0.01, width: 112);
  static final bodyL = _mona(16, 24, 430);
  static final bodyLMedium = _mona(16, 24, 560);
  static final body = _mona(15, 22, 430, tracking: 0.005, color: PrepColors.text2);

  /// The primary button label.
  static final button = _mona(16, 20, 720, tracking: -0.005, width: 110);
  static final label = _mona(14, 20, 680, tracking: 0.01, width: 106);
  static final meta = _mona(13, 18, 520, tracking: 0.01, color: PrepColors.text2);

  /// Small print (helper and legal lines). Never below 12.
  static final caption = _mona(12, 16, 560, tracking: 0.02, color: PrepColors.text3);
  static final timer = _mona(22, 26, 600, width: 100, features: const [FontFeature.tabularFigures()]);
  static final wordmark = _mona(18, 23, 820, tracking: -0.02, width: 125);
}
