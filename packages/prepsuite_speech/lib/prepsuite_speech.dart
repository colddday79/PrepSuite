/// Offline speech for PrepSuite: speech-to-text with word timings, delivery
/// metrics and the Norman interviewer voice. See README.md.
library;

export 'src/norman_voice.dart' show NormanVoice;
export 'src/offline_speech_capture.dart' show OfflineSpeechCapture;
export 'src/speech_models.dart' show SpeechModels, SpeechModelPaths, SpeechModelsMissing;
export 'src/wav_replay_recorder.dart' show WavReplayRecorder;
export 'src/types.dart'
    show TimedWord, Transcript, DeliveryMetrics, CaptureResult, SpeechCapture, InterviewerVoice;
