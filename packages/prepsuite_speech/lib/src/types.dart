/// Public value types and interfaces of `prepsuite_speech`.
library;

/// One recognised word with its position in the saved recording.
///
/// Times are milliseconds from the start of the WAV file. `startMs` comes from
/// the recogniser's token timestamps; `endMs` is estimated from the audio
/// energy after the word's last token (capped by the next word's start).
class TimedWord {
  final String text;
  final int startMs;
  final int endMs;
  const TimedWord(this.text, this.startMs, this.endMs);

  Map<String, dynamic> toJson() => {'text': text, 'start_ms': startMs, 'end_ms': endMs};

  @override
  String toString() => '$text[$startMs-$endMs]';
}

/// Text of a recording plus word timings. [onDevice] is true when the
/// transcript was produced on the phone (always true for this package).
class Transcript {
  final String text;
  final List<TimedWord> words;
  final bool onDevice;
  const Transcript(this.text, this.words, this.onDevice);

  static const empty = Transcript('', [], true);

  Map<String, dynamic> toJson() => {
        'text': text,
        'words': [for (final w in words) w.toJson()],
        'on_device': onDevice,
      };
}

/// Objective measurements of how the user spoke.
///
/// Loudness values are dBFS (20·log10 of frame RMS, full scale = 1.0) over
/// voiced frames only, so they depend on the microphone and distance.
/// `speechRatio` is the share of the speaking span (first to last voiced
/// frame) that is not a silence of 200 ms or more.
class DeliveryMetrics {
  final double durationS;
  final int words;
  final int wpm;
  final int pausesOver1s;
  final double longestPauseS;
  final int fillerCount;
  final Map<String, int> fillers;
  final double loudnessDbMean;
  final double loudnessDbSd;
  final bool trailingOff;
  final double? pitchHzMean;
  final double? pitchSemitoneSd;
  final bool? monotone;
  final double speechRatio;

  const DeliveryMetrics({
    required this.durationS,
    required this.words,
    required this.wpm,
    required this.pausesOver1s,
    required this.longestPauseS,
    required this.fillerCount,
    required this.fillers,
    required this.loudnessDbMean,
    required this.loudnessDbSd,
    required this.trailingOff,
    required this.pitchHzMean,
    required this.pitchSemitoneSd,
    required this.monotone,
    required this.speechRatio,
  });

  Map<String, dynamic> toJson() => {
        'duration_s': _round(durationS, 2),
        'words': words,
        'wpm': wpm,
        'pauses_over_1s': pausesOver1s,
        'longest_pause_s': _round(longestPauseS, 2),
        'filler_count': fillerCount,
        'fillers': Map<String, int>.of(fillers),
        'loudness_db_mean': _round(loudnessDbMean, 1),
        'loudness_db_sd': _round(loudnessDbSd, 1),
        'trailing_off': trailingOff,
        'pitch_hz_mean': pitchHzMean == null ? null : _round(pitchHzMean!, 1),
        'pitch_semitone_sd': pitchSemitoneSd == null ? null : _round(pitchSemitoneSd!, 2),
        'monotone': monotone,
        'speech_ratio': _round(speechRatio, 3),
      };

  factory DeliveryMetrics.fromJson(Map<String, dynamic> j) => DeliveryMetrics(
        durationS: (j['duration_s'] as num).toDouble(),
        words: j['words'] as int,
        wpm: j['wpm'] as int,
        pausesOver1s: j['pauses_over_1s'] as int,
        longestPauseS: (j['longest_pause_s'] as num).toDouble(),
        fillerCount: j['filler_count'] as int,
        fillers: Map<String, int>.from(j['fillers'] as Map),
        loudnessDbMean: (j['loudness_db_mean'] as num).toDouble(),
        loudnessDbSd: (j['loudness_db_sd'] as num).toDouble(),
        trailingOff: j['trailing_off'] as bool,
        pitchHzMean: (j['pitch_hz_mean'] as num?)?.toDouble(),
        pitchSemitoneSd: (j['pitch_semitone_sd'] as num?)?.toDouble(),
        monotone: j['monotone'] as bool?,
        speechRatio: (j['speech_ratio'] as num).toDouble(),
      );

  @override
  String toString() => 'DeliveryMetrics(${toJson()})';
}

double _round(double v, int places) {
  if (!v.isFinite) return v;
  final f = [1, 10, 100, 1000, 10000][places];
  return (v * f).roundToDouble() / f;
}

/// Everything produced for one answer. [wavPath] is a 16-bit PCM WAV kept in
/// app-private storage; [peakLevel] is the largest absolute sample (0..1),
/// useful to spot a silent or clipping microphone.
class CaptureResult {
  final String wavPath;
  final int durationMs;
  final Transcript transcript;
  final DeliveryMetrics metrics;
  final double peakLevel;
  const CaptureResult(this.wavPath, this.durationMs, this.transcript, this.metrics, this.peakLevel);
}

/// Microphone capture with live partial text; everything runs on the phone.
abstract class SpeechCapture {
  /// Smoothed input level, 0..1, while recording.
  Stream<double> get level;

  /// Live partial transcript while recording.
  Stream<String> get partialText;

  /// Starts recording. Returns false if the microphone permission is denied,
  /// models are unavailable, or a recording is already running. Recording
  /// stops by itself after [maxDuration]; call [stop] to get the result.
  Future<bool> start({required Duration maxDuration});

  /// Stops recording and returns the transcript and metrics (null if nothing
  /// was recording or processing failed).
  Future<CaptureResult?> stop();

  /// Stops recording and discards the audio.
  Future<void> cancel();

  /// Transcribes and measures an existing WAV file (PCM16 or float32).
  Future<CaptureResult?> transcribeFile(String wavPath);
}

/// The AI interviewer's voice.
abstract class InterviewerVoice {
  /// Output level, 0..1, while speaking (drives the orb).
  Stream<double> get level;

  /// Speaks [text]; completes when playback ends or [stop] is called.
  Future<void> speak(String text);

  /// Cuts speech off immediately.
  Future<void> stop();
}
