import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// A warm near-black room lit by the gold presence, with gold as the one accent.
/// Ported from the native HomePalette. Text pairs measured on [bg]:
/// text 17:1, text2 9.5:1, text3 6.2:1, accent 10:1.
abstract final class PrepColors {
  static const bg = Color(0xFF0E0C0A);
  static const surface1 = Color(0xFF171410);
  static const surface2 = Color(0xFF211D18);
  static const line = Color(0xFF2A251F);
  static const lineStrong = Color(0xFF3D362D);
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
  static const press = Color(0xFF808080);
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
  static const press = Duration(milliseconds: 100);
  static const fade = Duration(milliseconds: 200);
  static const enter = Duration(milliseconds: 300);
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
    fontVariations: [FontVariation.weight(weight), FontVariation.width(width)],
    fontFeatures: features,
    color: color,
  );
}

/// Mona Sans only. Sizes and line heights match the native type scale.
abstract final class PrepType {
  /// The one big line on Home, under the presence.
  static final display = _mona(30, 36, 600, tracking: -0.025);
  static final question = _mona(25, 34, 500, tracking: -0.02);
  static final questionM = _mona(20, 28, 500, tracking: -0.01);
  static final headline = _mona(28, 35, 700, tracking: -0.02);
  static final quote = _mona(16, 25, 400, tracking: 0.005);
  static final titleM = _mona(17, 23, 600, tracking: -0.01);
  static final bodyL = _mona(16, 24, 400);
  static final bodyLMedium = _mona(16, 24, 500);
  static final body = _mona(15, 23, 400, tracking: 0.005, color: PrepColors.text2);
  static final label = _mona(14, 20, 600, tracking: 0.01);
  static final meta = _mona(13, 18, 500, tracking: 0.01, color: PrepColors.text2);
  static final timer = _mona(22, 26, 400, width: 88, features: const [FontFeature.tabularFigures()]);
  static final wordmark = _mona(18, 23, 700, tracking: -0.02);
}
