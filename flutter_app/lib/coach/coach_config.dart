import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Where the app finds the coach server.
class CoachConfig {
  // Override: flutter run --dart-define=COACH_URL=http://192.168.x.x:8787/coach
  static const String fromDefine = String.fromEnvironment('COACH_URL');

  /// The COACH_URL define when set, else the dev server on this computer
  /// (10.0.2.2 is the host machine as seen from the Android emulator).
  static Uri endpoint() {
    final raw = fromDefine.trim();
    if (raw.isNotEmpty) {
      final uri = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        return uri;
      }
      debugPrint(
        'COACH_URL "$raw" is not a valid http(s) URL. Using the default.',
      );
    }
    if (!kIsWeb && Platform.isAndroid) {
      return Uri.parse('http://10.0.2.2:8787/coach');
    }
    return Uri.parse('http://localhost:8787/coach');
  }
}
