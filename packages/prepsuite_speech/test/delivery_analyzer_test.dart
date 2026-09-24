import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite_speech/delivery_analyzer.dart';

const sr = 16000;

/// Builds a signal from segments: (seconds, amplitude, startHz, endHz).
/// amplitude 0 = digital silence. Frequency glides linearly (in log space).
Float32List signal(List<(double, double, double, double)> segments, {double noise = 0, int seed = 1}) {
  final total = segments.fold<double>(0, (a, s) => a + s.$1);
  final out = Float32List((total * sr).round());
  final rnd = math.Random(seed);
  var i = 0;
  var phase = 0.0;
  for (final (secs, amp, f0, f1) in segments) {
    final n = (secs * sr).round();
    for (var k = 0; k < n && i < out.length; k++, i++) {
      final t = k / n;
      final f = f0 * math.pow(f1 / f0, t);
      phase += 2 * math.pi * f / sr;
      // Harmonic-rich "voice": fundamental plus two harmonics.
      final v = math.sin(phase) + 0.5 * math.sin(2 * phase) + 0.25 * math.sin(3 * phase);
      out[i] = (amp * v / 1.75) + (noise > 0 ? noise * (rnd.nextDouble() * 2 - 1) : 0);
    }
  }
  return out;
}

Transcript words(int n, {String? text}) {
  final w = [for (var i = 0; i < n; i++) TimedWord('w$i', i * 300, i * 300 + 250)];
  return Transcript(text ?? w.map((e) => e.text).join(' '), w, true);
}

void main() {
  const analyzer = DeliveryAnalyzer();

  test('steady 200 Hz tone: pitch, loudness, monotone, no pauses', () {
    final x = signal([(3.0, 0.5, 200, 200)]);
    final m = analyzer.analyze(x, sr, Transcript.empty);
    expect(m.durationS, closeTo(3.0, 1e-6));
    expect(m.pitchHzMean!, closeTo(200, 2));
    expect(m.pitchSemitoneSd!, lessThan(0.2));
    expect(m.monotone, isTrue);
    expect(m.pausesOver1s, 0);
    expect(m.longestPauseS, 0);
    expect(m.speechRatio, closeTo(1.0, 1e-9));
    expect(m.trailingOff, isFalse);
    expect(m.loudnessDbSd, lessThan(0.5));
    // RMS of the 3-harmonic wave: 0.5/1.75 * sqrt((1 + .25 + .0625)/2).
    final rms = 0.5 / 1.75 * math.sqrt((1 + 0.25 + 0.0625) / 2);
    expect(m.loudnessDbMean, closeTo(20 * math.log(rms) / math.ln10, 0.3));
  });

  test('one-octave glide is not monotone (sd ~ 12/sqrt(12) st)', () {
    final x = signal([(4.0, 0.4, 120, 240)]);
    final m = analyzer.analyze(x, sr, Transcript.empty);
    expect(m.monotone, isFalse);
    expect(m.pitchSemitoneSd!, closeTo(12 / math.sqrt(12), 0.35));
    expect(m.pitchHzMean!, greaterThan(150));
    expect(m.pitchHzMean!, lessThan(190));
  });

  test('pauses: >1 s gaps counted, leading/trailing silence ignored', () {
    final x = signal([
      (0.8, 0, 1, 1),
      (1.0, 0.4, 180, 180),
      (1.5, 0, 1, 1),
      (1.0, 0.4, 180, 180),
      (0.5, 0, 1, 1),
      (1.0, 0.4, 180, 180),
      (1.2, 0, 1, 1),
    ]);
    final m = analyzer.analyze(x, sr, words(10));
    expect(m.durationS, closeTo(7.0, 1e-6));
    expect(m.pausesOver1s, 1);
    expect(m.longestPauseS, closeTo(1.5, 0.06));
    // Speaking span 5.0 s, of which 3.0 s voiced.
    expect(m.speechRatio, closeTo(0.6, 0.03));
    // 10 words over the 5 s speaking span.
    expect(m.words, 10);
    expect(m.wpm, closeTo(120, 3));
  });

  test('pause detection survives background noise', () {
    final x = signal([
      (0.5, 0, 1, 1),
      (1.5, 0.3, 150, 150),
      (2.0, 0, 1, 1),
      (1.5, 0.3, 150, 150),
      (0.5, 0, 1, 1),
    ], noise: 0.003);
    final m = analyzer.analyze(x, sr, Transcript.empty);
    expect(m.pausesOver1s, 1);
    expect(m.longestPauseS, closeTo(2.0, 0.08));
  });

  test('trailing off: last fifth 8 dB quieter', () {
    final quietEnd = signal([(4.0, 0.5, 160, 160), (1.0, 0.2, 160, 160)]);
    expect(analyzer.analyze(quietEnd, sr, Transcript.empty).trailingOff, isTrue);
    final steady = signal([(5.0, 0.5, 160, 160)]);
    expect(analyzer.analyze(steady, sr, Transcript.empty).trailingOff, isFalse);
  });

  test('silence: nothing voiced, pitch/monotone null', () {
    final x = Float32List(sr * 3);
    final m = analyzer.analyze(x, sr, Transcript.empty);
    expect(m.words, 0);
    expect(m.wpm, 0);
    expect(m.speechRatio, 0);
    expect(m.pitchHzMean, isNull);
    expect(m.monotone, isNull);
    expect(m.loudnessDbMean, -100);
  });

  test('under 2 s of voicing: monotone is null but pitch is measured', () {
    final x = signal([(0.5, 0, 1, 1), (1.5, 0.4, 220, 220), (0.5, 0, 1, 1)]);
    final m = analyzer.analyze(x, sr, Transcript.empty);
    expect(m.pitchHzMean!, closeTo(220, 3));
    expect(m.monotone, isNull);
  });

  test('fillers are counted from the transcript', () {
    final x = signal([(3.0, 0.4, 150, 150)]);
    final m = analyzer.analyze(
      x,
      sr,
      const Transcript('So, um, I basically, uh, fixed it. Um, yes.', [], true),
    );
    expect(m.fillers, {'um': 2, 'basically': 1, 'uh': 1});
    expect(m.fillerCount, 4);
    expect(m.words, 9);
  });

  test('toJson has the contract keys', () {
    final m = analyzer.analyze(signal([(3.0, 0.4, 150, 150)]), sr, words(5));
    expect(m.toJson().keys, [
      'duration_s', 'words', 'wpm', 'pauses_over_1s', 'longest_pause_s', 'filler_count',
      'fillers', 'loudness_db_mean', 'loudness_db_sd', 'trailing_off', 'pitch_hz_mean',
      'pitch_semitone_sd', 'monotone', 'speech_ratio',
    ]);
    final back = DeliveryMetrics.fromJson(m.toJson());
    expect(back.toJson(), m.toJson());
  });

  test('refineWordEnds follows voicing but never passes the next word', () {
    final x = signal([(0.5, 0, 1, 1), (0.6, 0.4, 150, 150), (1.0, 0, 1, 1), (0.5, 0.4, 150, 150)]);
    final fa = analyzer.frames(x, sr);
    final refined = analyzer.refineWordEnds(const [
      TimedWord('hello', 520, 800), // voiced until 1100 ms
      TimedWord('there', 2150, 2400), // voiced until 2600 ms
    ], fa);
    expect(refined[0].endMs, closeTo(1100, 30));
    expect(refined[1].endMs, closeTo(2600, 30));
  });
}
