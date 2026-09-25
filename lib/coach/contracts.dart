// The speech contract shared by the app, the speech package and the coach
// server. packages/prepsuite_speech is the single source of truth: these are
// its types, re-exported so app code does not depend on the package directly.
export 'package:prepsuite_speech/prepsuite_speech.dart'
    show CaptureResult, DeliveryMetrics, InterviewerVoice, SpeechCapture, TimedWord, Transcript;
