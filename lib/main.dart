import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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

/// Canned microphone data is available only for explicitly requested demos.
const bool _demoSpeech = bool.fromEnvironment('SPEECH_DEMO');

/// The existing local voice is replaceable when the final voice is selected.
/// Use INTERVIEWER_VOICE=none to keep questions on screen without read-aloud.
const String _interviewerVoice = String.fromEnvironment(
  'INTERVIEWER_VOICE',
  defaultValue: 'norman',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Mona Sans',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  HologramVideo.instance.ensure();
  runApp(PrepSuiteApp(services: createServices()));
}

AppServices createServices() {
  final endpoint = CoachConfig.endpoint();
  final CoachApi coach = _fakeCoach
      ? FakeCoachApi()
      : HttpCoachApi(endpoint: endpoint);

  final SpeechCapture speech = _demoSpeech
      ? FakeSpeechCapture()
      : SpeechCaptureAdapter();
  final InterviewerVoice voice = _demoSpeech
      ? FakeInterviewerVoice()
      : _interviewerVoice == 'none'
      ? TextOnlyInterviewerVoice()
      : InterviewerVoiceAdapter();

  return AppServices(
    coach: coach,
    speech: speech,
    voice: voice,
    consent: PrefsConsentStore(),
    sessions: SessionStore(persist: true),
    mic: PluginMicPermission(),
    coachLabel: _fakeCoach
        ? 'Built-in sample coach (COACH_FAKE)'
        : endpoint.toString(),
    speechLabel: speech is FakeSpeechCapture
        ? 'Demo voice input: it plays back a sample answer instead of listening.'
        : 'English speech is transcribed on this phone. Recordings are deleted after transcription.',
  );
}
