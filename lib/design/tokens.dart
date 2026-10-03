import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// One complete colour world. Every theme is dark and composed on its own (never an inverted
/// light theme): a near-black canvas, satin metal surfaces, warm or cool greys for text, and one
/// accent spent only on the main action, the active state and real progress.
@immutable
class PrepThemeData {
  const PrepThemeData({
    required this.id,
    required this.name,
    required this.canvas,
    required this.metalTop,
    required this.metalBottom,
    required this.metalRaised,
    required this.rimLight,
    required this.hairline,
    required this.hairlineStrong,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.onAccent,
    required this.accentDeep,
  });

  final String id;
  final String name;

  /// The page.
  final Color canvas;

  /// Card metal: a same-hue vertical gradient from [metalTop] to [metalBottom].
  final Color metalTop;
  final Color metalBottom;

  /// Discs, chips and the tab bar: one step lighter than a card.
  final Color metalRaised;

  /// The 1 px highlight along a card's top edge.
  final Color rimLight;
  final Color hairline;
  final Color hairlineStrong;
  final Color text;
  final Color text2;
  final Color text3;

  /// The main action and the active state.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// The accent as text, arcs and ticks on metal.
  final Color accentDeep;
}

/// The three themes the person can switch between in Profile, Appearance. WCAG contrast on card
/// metal ([PrepThemeData.metalTop]) is asserted in test/design_test.dart for every theme: text2
/// at least 7:1, text3 and accentDeep at least 4.5:1, onAccent on the accent at least 4.5:1.
abstract final class PrepThemes {
  /// Warm black with an amber accent (the default).
  static const ember = PrepThemeData(
    id: 'ember',
    name: 'Ember',
    canvas: Color(0xFF0E0C0B),
    metalTop: Color(0xFF1D1A18),
    metalBottom: Color(0xFF151311),
    metalRaised: Color(0xFF26221F),
    rimLight: Color(0x17FFFFFF),
    hairline: Color(0xFF2E2A26),
    hairlineStrong: Color(0xFF3E3934),
    text: Color(0xFFF3EEE9),
    text2: Color(0xFFBDB4AC),
    text3: Color(0xFF9A918A),
    accent: Color(0xFFF07A35),
    onAccent: Color(0xFF1A0E06),
    accentDeep: Color(0xFFF58C4C),
  );

  /// Cool graphite with a signal red.
  static const signal = PrepThemeData(
    id: 'signal',
    name: 'Signal',
    canvas: Color(0xFF0B0C0E),
    metalTop: Color(0xFF1B1C20),
    metalBottom: Color(0xFF131417),
    metalRaised: Color(0xFF23252A),
    rimLight: Color(0x17FFFFFF),
    hairline: Color(0xFF2A2C31),
    hairlineStrong: Color(0xFF3A3D44),
    text: Color(0xFFF2F3F5),
    text2: Color(0xFFB3B7BF),
    text3: Color(0xFF90959E),
    accent: Color(0xFFFF4D5A),
    onAccent: Color(0xFF1A0508),
    accentDeep: Color(0xFFFF6672),
  );

  /// Dark bronze with a brass accent.
  static const brass = PrepThemeData(
    id: 'brass',
    name: 'Brass',
    canvas: Color(0xFF0D0C0A),
    metalTop: Color(0xFF1C1A16),
    metalBottom: Color(0xFF14130F),
    metalRaised: Color(0xFF25221C),
    rimLight: Color(0x17FFF3D6),
    hairline: Color(0xFF2E2B24),
    hairlineStrong: Color(0xFF3F3B31),
    text: Color(0xFFF4F0E4),
    text2: Color(0xFFBEB6A2),
    text3: Color(0xFF999281),
    accent: Color(0xFFE2B755),
    onAccent: Color(0xFF1A1404),
    accentDeep: Color(0xFFE8C46E),
  );

  static const all = [ember, signal, brass];

  static PrepThemeData byId(String? id) => all.firstWhere((t) => t.id == id, orElse: () => ember);
}

/// The current theme's roles under the names every screen already uses. They are getters, not
/// constants, so switching the theme and rebuilding the app repaints everything.
abstract final class PrepColors {
  static PrepThemeData _theme = PrepThemes.ember;

  /// The theme now in use.
  static PrepThemeData get theme => _theme;

  /// Switches the theme; the app root rebuilds everything after calling it.
  static void useTheme(PrepThemeData theme) => _theme = theme;

  static Color get bg => _theme.canvas;

  /// Flat card colour, where a gradient can't be used (fields, sheets).
  static Color get surface1 => _theme.metalTop;
  static Color get surface2 => _theme.metalRaised;
  static Color get metalTop => _theme.metalTop;
  static Color get metalBottom => _theme.metalBottom;
  static Color get rimLight => _theme.rimLight;
  static const rimDark = Color(0x73000000);
  static Color get line => _theme.hairline;
  static Color get lineStrong => _theme.hairlineStrong;
  static Color get text => _theme.text;
  static Color get text2 => _theme.text2;
  static Color get text3 => _theme.text3;

  /// The main action's fill (the accent), with [onAccent] on it.
  static Color get ink => _theme.accent;
  static Color get accent => _theme.accent;
  static Color get onAccent => _theme.onAccent;
  static Color get accentDeep => _theme.accentDeep;

  /// The accent at low strength over a card, for selected rows and tiles.
  static Color get accentSoft => Color.alphaBlend(_theme.accent.withValues(alpha: 0.14), _theme.metalTop);
  static Color get accentTint => accentSoft;

  /// Keyboard, D-pad and switch-access focus ring.
  static Color get focus => _theme.accentDeep;

  static const danger = Color(0xFFFF6B5E);
  static const recording = Color(0xFFFF5A4F);
  static const success = Color(0xFF5FCB8D);
  static const warning = Color(0xFFF2B35A);
  static Color get successTint => Color.alphaBlend(success.withValues(alpha: 0.14), _theme.metalTop);
  static Color get warningTint => Color.alphaBlend(warning.withValues(alpha: 0.14), _theme.metalTop);
  static Color get glassBorder => _theme.rimLight;
  static Color get glassBg => _theme.metalRaised.withValues(alpha: 0.86);
  static Color get cardHighlight => _theme.rimLight;

  /// Press tint, on the accent and on metal alike.
  static Color get press => _theme.text3;

  /// Behind dialogs and sheets.
  static const scrim = Color(0xB3000000);

  /// Kept for older call sites: the coach colour no longer tints the chrome (it lives in the robot).
  static void useAccent(Color deep, [Color? soft]) {}
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
  static const double card = 22;
  static const double sheet = 28;
  static const double pill = 30;
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
  Color? color,
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
    color: color ?? PrepColors.text,
  );
}

/// Mona Sans only. Large type carries the hierarchy so screens need few words: big light numerals,
/// a firm display and titles slightly widened, regular body with a touch more weight and tracking
/// for light-on-dark reading. Getters, so text follows the current theme.
abstract final class PrepType {
  /// Big numbers: "2/8", "0:42", "3".
  static TextStyle get numeral => _mona(56, 56, 300, tracking: -0.02, features: const [FontFeature.tabularFigures()]);

  /// The one big line at the top of a tab ("Hi, Alex", "Practice").
  static TextStyle get display => _mona(32, 36, 640, tracking: -0.025, width: 108);
  static TextStyle get question => _mona(26, 32, 560, tracking: -0.015);
  static TextStyle get questionM => _mona(21, 27, 560, tracking: -0.01);
  static TextStyle get headline => _mona(26, 31, 640, tracking: -0.02, width: 106);

  /// Card, dialog and sheet titles, a step above [titleM].
  static TextStyle get titleL => _mona(21, 26, 620, tracking: -0.015, width: 104);
  static TextStyle get quote => _mona(16, 25, 450, tracking: 0.01, color: PrepColors.text2);
  static TextStyle get titleM => _mona(17, 22, 620, tracking: -0.005, width: 104);
  static TextStyle get bodyL => _mona(16, 24, 450, tracking: 0.01);
  static TextStyle get bodyLMedium => _mona(16, 24, 560, tracking: 0.005);
  static TextStyle get body => _mona(15, 22, 450, tracking: 0.01, color: PrepColors.text2);

  /// The primary button label.
  static TextStyle get button => _mona(16, 20, 650, width: 105);
  static TextStyle get label => _mona(14, 18, 580, tracking: 0.01);
  static TextStyle get meta => _mona(13, 18, 500, tracking: 0.015, color: PrepColors.text2);

  /// Small print. Never below 12.
  static TextStyle get caption => _mona(12, 16, 540, tracking: 0.02, color: PrepColors.text3);
  static TextStyle get timer => _mona(22, 26, 400, features: const [FontFeature.tabularFigures()]);
  static TextStyle get wordmark => _mona(18, 23, 700, tracking: -0.01, width: 108);
}
