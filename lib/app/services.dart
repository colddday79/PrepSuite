import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../coach/coach_api.dart';
import '../coach/contracts.dart';
import '../coach/speech_adapter.dart';
import 'session.dart';

/// Everything a screen needs from the outside world. Swapped wholesale in tests.
class AppServices {
  AppServices({
    required this.coach,
    required this.speech,
    required this.voice,
    required this.consent,
    required this.mic,
    required this.coachLabel,
    required this.speechLabel,
    SessionStore? sessions,
    SpeechSetup? speechSetup,
  }) : sessions = sessions ?? SessionStore(),
       speechSetup = speechSetup ?? SpeechSetup.ready();

  final CoachApi coach;
  final SpeechCapture speech;
  final InterviewerVoice voice;
  final ConsentStore consent;
  final MicPermission mic;

  /// Where the coach lives, shown in Settings so a broken connection is easy to diagnose.
  final String coachLabel;

  /// Which speech engine is running (the demo stand-in or the on-device recognizer).
  final String speechLabel;

  final SessionStore sessions;

  /// Offline speech preparation (model copy on first launch, then loading), started at launch.
  final SpeechSetup speechSetup;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above $context');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

/// Remembers that the person agreed to how their voice and text are handled.
abstract class ConsentStore {
  Future<bool> accepted();
  Future<void> accept();
}

class PrefsConsentStore implements ConsentStore {
  static const _key = 'consent.voice_to_text.v2';

  @override
  Future<bool> accepted() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> accept() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {
      // Worst case the sheet shows again next launch.
    }
  }
}

class MemoryConsentStore implements ConsentStore {
  MemoryConsentStore({this.value = false});

  bool value;

  @override
  Future<bool> accepted() async => value;

  @override
  Future<void> accept() async => value = true;
}

enum MicAccess { granted, denied, blocked }

/// Asks for the microphone only when the person first taps record.
abstract class MicPermission {
  Future<MicAccess> request();
  Future<void> openSettings();
}

class PluginMicPermission implements MicPermission {
  @override
  Future<MicAccess> request() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted || status.isLimited) return MicAccess.granted;
      if (status.isPermanentlyDenied || status.isRestricted) return MicAccess.blocked;
      return MicAccess.denied;
    } catch (_) {
      return MicAccess.denied;
    }
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

class GrantedMicPermission implements MicPermission {
  GrantedMicPermission({this.access = MicAccess.granted});

  MicAccess access;
  int requests = 0;

  @override
  Future<MicAccess> request() async {
    requests++;
    return access;
  }

  @override
  Future<void> openSettings() async {}
}
