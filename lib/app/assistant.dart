import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which assistant the person practices with. The four robots differ only in colour; the orb is the
/// original gold hologram. They all use the same coach and the same voice.
enum AssistantKind { nova, sol, iris, mint, orb }

@immutable
class AssistantLook {
  const AssistantLook._(this.kind, this.name, this.colour, this.glow, this.tone);

  final AssistantKind kind;

  /// What the assistant is called in the app ("Tide").
  final String name;

  /// The colour, said plainly for the picker and screen readers ("Blue").
  final String colour;

  /// The face and lights colour, matched to the render's emission colour.
  final Color glow;

  /// The coach's own colour for buttons, selection and progress. Each coach has a clearly different
  /// hue (blue, amber, violet, green, gold), softer than the [glow] so the chrome never looks neon.
  /// Dark text on it clears 7:1 (asserted in test/design_test.dart).
  final Color tone;

  bool get isRobot => kind != AssistantKind.orb;

  String get bodyAsset => 'assets/assistant/${kind.name}_body.webp';
  String get glassAsset => 'assets/assistant/${kind.name}_glass.webp';
  String get glowAsset => 'assets/assistant/${kind.name}_glow.webp';

  static const nova = AssistantLook._(AssistantKind.nova, 'Tide', 'Blue', Color(0xFF45D0FF), Color(0xFF78A6F0));
  static const sol = AssistantLook._(AssistantKind.sol, 'Ember', 'Amber', Color(0xFFFFA45E), Color(0xFFF39A5E));
  static const iris = AssistantLook._(AssistantKind.iris, 'Echo', 'Violet', Color(0xFFC09CFF), Color(0xFFB39DF5));
  static const mint = AssistantLook._(AssistantKind.mint, 'Sprout', 'Green', Color(0xFF4DF7CF), Color(0xFF63CC98));
  static const orb = AssistantLook._(AssistantKind.orb, 'Orbit', 'Gold', Color(0xFFE6B35E), Color(0xFFE2BE62));

  static const all = [nova, sol, iris, mint, orb];

  static AssistantLook of(AssistantKind kind) => all.firstWhere((l) => l.kind == kind);
}

/// The chosen assistant and whether first-run onboarding is done. Saved on this phone when [persist]
/// is on; tests keep it in memory and start already onboarded.
class AssistantStore extends ChangeNotifier implements ValueListenable<AssistantLook> {
  AssistantStore({this.persist = false, AssistantKind initial = AssistantKind.nova, bool onboarded = true})
      : _look = AssistantLook.of(initial),
        _restored = !persist {
    _onboarded = onboarded;
  }

  static const _kindKey = 'assistant.kind.v1';
  static const _onboardedKey = 'onboarding.done.v1';

  final bool persist;
  AssistantLook _look;
  bool _onboarded = true;
  bool _restored;
  bool _disposed = false;
  int _revision = 0;

  @override
  AssistantLook get value => _look;

  /// First-run onboarding has been completed (or skipped).
  bool get onboarded => _onboarded;

  /// Saved choices have been read, so the app can decide between onboarding and Home.
  bool get restored => _restored;

  Future<void> restore() async {
    if (_restored) return;
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (revision == _revision) {
        final kind = prefs.getString(_kindKey);
        final match = AssistantKind.values.where((k) => k.name == kind);
        if (match.isNotEmpty) _look = AssistantLook.of(match.first);
        _onboarded = prefs.getBool(_onboardedKey) ?? false;
      }
    } catch (_) {
      // Unreadable preferences: start with the defaults.
    }
    _restored = true;
    _notify();
  }

  Future<void> choose(AssistantKind kind) async {
    _revision++;
    _look = AssistantLook.of(kind);
    _notify();
    if (!persist) return;
    try {
      await (await SharedPreferences.getInstance()).setString(_kindKey, kind.name);
    } catch (_) {
      // Worst case the default comes back next launch.
    }
  }

  Future<void> finishOnboarding() async {
    _revision++;
    _onboarded = true;
    _notify();
    if (!persist) return;
    try {
      await (await SharedPreferences.getInstance()).setBool(_onboardedKey, true);
    } catch (_) {
      // Worst case onboarding shows again next launch.
    }
  }

  /// Shows onboarding again (Settings, "See the introduction again").
  Future<void> resetOnboarding() async {
    _revision++;
    _onboarded = false;
    _notify();
    if (!persist) return;
    try {
      await (await SharedPreferences.getInstance()).setBool(_onboardedKey, false);
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
