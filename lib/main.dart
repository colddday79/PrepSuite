import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prepsuite_speech/prepsuite_speech.dart'
    show NormanVoice, OfflineSpeechCapture, WavReplayRecorder;

import 'app/app.dart';
import 'app/services.dart';
import 'app/session.dart';
import 'coach/coach_api.dart';
import 'coach/coach_config.dart';
import 'coach/contracts.dart';
import 'coach/fakes.dart';
import 'coach/speech_adapter.dart';
import 'design/hologram.dart';

/// Use the built-in sample coach instead of the server:
/// `flutter run --dart-define=COACH_FAKE=true`.
const bool _fakeCoach = bool.fromEnvironment('COACH_FAKE');

/// Canned speech instead of the microphone and Norman, for demos and UI work:
/// `flutter run --dart-define=SPEECH_FAKE=true` (SPEECH_DEMO=true also works).
const bool _fakeSpeech =
    bool.fromEnvironment('SPEECH_FAKE') || bool.fromEnvironment('SPEECH_DEMO');

/// Debug builds only, for the silent emulator microphone: comma-separated WAV
/// paths on the device. Each recording replays the next file through the real
/// speech pipeline in real time, then the microphone is used again. Ignored in
/// profile and release builds.
const String _testWavs = String.fromEnvironment('SPEECH_TEST_WAVS');

/// INTERVIEWER_VOICE=none keeps questions on screen without read-aloud.
const String _interviewerVoice = String.fromEnvironment(
  'INTERVIEWER_VOICE',
  defaultValue: 'norman',
);

/// Questions, feedback and notes can take a while from a real model.
const Duration _coachTimeout = Duration(seconds: 120);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Bodoni Moda'], await rootBundle.loadString('assets/fonts/BodoniModa-OFL.txt'));
    yield LicenseEntryWithLineBreaks(['Jost'], await rootBundle.loadString('assets/fonts/Jost-OFL.txt'));
  });
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  HologramVideo.instance.ensure();
  final services = createServices();
  runApp(PrepSuiteApp(services: services));
  // Copy the offline models on first launch and load them now, so the first
  // question is spoken at once. Screens show the progress if they get there
  // first; failures are shown there too.
  unawaited(services.speechSetup.prepare().catchError((Object _) {}));
}

AppServices createServices() {
  final endpoint = CoachConfig.endpoint();
  final CoachApi coach = _fakeCoach
      ? FakeCoachApi()
      : HttpCoachApi(endpoint: endpoint, timeout: _coachTimeout);
  final coachLabel = _fakeCoach
      ? 'Built-in sample coach (COACH_FAKE)'
      : endpoint.toString();

  if (_fakeSpeech) {
    return AppServices(
      coach: coach,
      speech: FakeSpeechCapture(),
      voice: FakeInterviewerVoice(),
      consent: PrefsConsentStore(),
      sessions: SessionStore(persist: true),
      mic: PluginMicPermission(),
      coachLabel: coachLabel,
      speechLabel:
          'Demo voice input (SPEECH_FAKE): it plays back a sample answer instead of listening.',
    );
  }

  final testWavs = kDebugMode ? _wavList(_testWavs) : const <String>[];
  final capture = OfflineSpeechCapture(
    recorder: testWavs.isEmpty
        ? null
        : WavReplayRecorder(
            testWavs,
            log: (line) => debugPrint('PrepSuite test audio: $line'),
          ),
  );
  final norman = _interviewerVoice == 'none' ? null : NormanVoice();
  final setup = SpeechSetup(
    warmUpCapture: capture.warmUp,
    warmUpVoice: norman?.warmUp,
  );
  final InterviewerVoice voice = norman == null
      ? TextOnlyInterviewerVoice()
      : InterviewerVoiceAdapter(voice: norman, setup: setup);

  return AppServices(
    coach: coach,
    speech: SpeechCaptureAdapter(capture: capture, setup: setup),
    voice: voice,
    consent: PrefsConsentStore(),
    sessions: SessionStore(persist: true),
    mic: PluginMicPermission(),
    speechSetup: setup,
    coachLabel: coachLabel,
    speechLabel: testWavs.isEmpty
        ? 'English speech is transcribed on this phone. Recordings are deleted after transcription.'
        : 'Debug test audio: recordings replay ${testWavs.length} WAV files, then use the microphone.',
  );
}

List<String> _wavList(String raw) => [
  for (final part in raw.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];
