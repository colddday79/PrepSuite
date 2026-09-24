// Shared contracts between the app, the speech package (packages/prepsuite_speech) and the coach
// server. Keep these names and fields exactly as they are: other packages code against them.

class TimedWord { final String text; final int startMs; final int endMs; const TimedWord(this.text, this.startMs, this.endMs); }
class Transcript { final String text; final List<TimedWord> words; final bool onDevice; const Transcript(this.text, this.words, this.onDevice); }
class DeliveryMetrics {
  final double durationS; final int words; final int wpm; final int pausesOver1s; final double longestPauseS;
  final int fillerCount; final Map<String, int> fillers; final double loudnessDbMean; final double loudnessDbSd;
  final bool trailingOff; final double? pitchHzMean; final double? pitchSemitoneSd; final bool? monotone; final double speechRatio;
  const DeliveryMetrics({required this.durationS, required this.words, required this.wpm, required this.pausesOver1s, required this.longestPauseS, required this.fillerCount, required this.fillers, required this.loudnessDbMean, required this.loudnessDbSd, required this.trailingOff, this.pitchHzMean, this.pitchSemitoneSd, this.monotone, required this.speechRatio});
  Map<String, dynamic> toJson() => { 'duration_s': durationS, 'words': words, 'wpm': wpm, 'pauses_over_1s': pausesOver1s, 'longest_pause_s': longestPauseS, 'filler_count': fillerCount, 'fillers': fillers, 'loudness_db_mean': loudnessDbMean, 'loudness_db_sd': loudnessDbSd, 'trailing_off': trailingOff, 'pitch_hz_mean': pitchHzMean, 'pitch_semitone_sd': pitchSemitoneSd, 'monotone': monotone, 'speech_ratio': speechRatio };
}
class CaptureResult { final String wavPath; final int durationMs; final Transcript transcript; final DeliveryMetrics metrics; final double peakLevel; const CaptureResult(this.wavPath, this.durationMs, this.transcript, this.metrics, this.peakLevel); }
abstract class SpeechCapture { Stream<double> get level; Stream<String> get partialText; Future<bool> start({required Duration maxDuration}); Future<CaptureResult?> stop(); Future<void> cancel(); Future<CaptureResult?> transcribeFile(String wavPath); }
abstract class InterviewerVoice { Stream<double> get level; Future<void> speak(String text); Future<void> stop(); }
