import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/tokens.dart';

/// Which colour theme the person picked in Profile, Appearance. Saved on this phone when [persist]
/// is on; tests keep it in memory. The app root listens and repaints everything on a change.
class ThemeStore extends ChangeNotifier implements ValueListenable<PrepThemeData> {
  ThemeStore({this.persist = false, PrepThemeData initial = PrepThemes.ember}) : _theme = initial;

  static const storageKey = 'theme.v1';

  final bool persist;
  PrepThemeData _theme;
  bool _disposed = false;

  @override
  PrepThemeData get value => _theme;

  Future<void> restore() async {
    if (!persist) return;
    try {
      final id = (await SharedPreferences.getInstance()).getString(storageKey);
      final theme = PrepThemes.byId(id);
      if (theme != _theme) {
        _theme = theme;
        _notify();
      }
    } catch (_) {
      // Unreadable preferences: keep the default.
    }
  }

  Future<void> choose(PrepThemeData theme) async {
    if (theme == _theme) return;
    _theme = theme;
    _notify();
    if (!persist) return;
    try {
      await (await SharedPreferences.getInstance()).setString(storageKey, theme.id);
    } catch (_) {
      // Worst case the default comes back next launch.
    }
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
