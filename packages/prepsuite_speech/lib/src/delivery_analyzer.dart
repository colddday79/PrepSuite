/// Delivery measurements from raw audio + transcript (pure Dart, no Flutter).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'fillers.dart';
import 'types.dart';

/// Per-frame view of a recording.
class FrameAnalysis {
  /// Frame length and hop in milliseconds.
  final int frameMs;

  /// Frame RMS level in dBFS (floored at -100).
  final Float64List db;

  /// Frames above the adaptive energy threshold (short blips removed).
  final List<bool> voiced;

  /// [voiced] with gaps shorter than [DeliveryAnalyzer.bridgeMs] filled:
  /// "is speaking" vs "is pausing".
  final List<bool> active;

  /// Energy threshold used, dBFS (null when the recording is silent).
  final double? thresholdDb;

  const FrameAnalysis(this.frameMs, this.db, this.voiced, this.active, this.thresholdDb);

  int get length => db.length;

  /// Index of the first/last active frame, or -1 when nothing was voiced.
  int get firstActive => active.indexOf(true);
  int get lastActive => active.lastIndexOf(true);
}

/// Computes [DeliveryMetrics]. Defaults follow the PrepSuite spec: 25 ms
/// frames, pauses > 1 s between voiced regions, pitch 60–400 Hz by YIN,
/// monotone when pitch SD < 1.5 semitones (null under 2 s of voicing).
class DeliveryAnalyzer {
  final int frameMs;
  final double pauseS;
  final int bridgeMs;
  final int minVoicedRunMs;
  final double minPitchHz;
  final double maxPitchHz;
  final double yinThreshold;
  final double monotoneSemitones;
  final double monotoneMinVoicedS;
  final double trailingOffDb;

  const DeliveryAnalyzer({
    this.frameMs = 25,
    this.pauseS = 1.0,
    this.bridgeMs = 200,
    this.minVoicedRunMs = 60,
    this.minPitchHz = 60,
    this.maxPitchHz = 400,
    this.yinThreshold = 0.2,
    this.monotoneSemitones = 1.5,
    this.monotoneMinVoicedS = 2.0,
    this.trailingOffDb = 4.0,
  });

  /// Convenience: frames + metrics in one call.
  DeliveryMetrics analyze(Float32List samples, int sampleRate, Transcript transcript) =>
      metrics(frames(samples, sampleRate), samples, sampleRate, transcript);

  /// Frame levels and voicing with an adaptive threshold:
  /// `max(floor + 10 dB, peak - 35 dB, -60 dBFS)` where floor/peak are the
  /// 10th/97th percentile frame levels, or `peak - 20 dB` when floor and peak
  /// are within 15 dB (a recording with almost no silence).
  FrameAnalysis frames(Float32List samples, int sampleRate) {
    final frameLen = math.max(1, sampleRate * frameMs ~/ 1000);
    final nFrames = samples.length ~/ frameLen;
    final db = Float64List(nFrames);
    for (var f = 0; f < nFrames; f++) {
      var sum = 0.0;
      final base = f * frameLen;
      for (var j = 0; j < frameLen; j++) {
        final v = samples[base + j];
        sum += v * v;
      }
      final rms = math.sqrt(sum / frameLen);
      db[f] = rms > 1e-5 ? 20 * math.log(rms) / math.ln10 : -100.0;
    }
    final voiced = List<bool>.filled(nFrames, false);
    double? threshold;
    if (nFrames > 0) {
      final sorted = Float64List.fromList(db)..sort();
      final floor = _percentile(sorted, 0.10);
      final peak = _percentile(sorted, 0.97);
      if (peak >= -60) {
        // Little contrast means there is hardly any silence to learn the
        // floor from: then everything within 20 dB of the peak is voice.
        final t = peak - floor < 15
            ? peak - 20
            : math.max(math.max(floor + 10, peak - 35), -60.0);
        threshold = t;
        for (var f = 0; f < nFrames; f++) {
          voiced[f] = db[f] >= t;
        }
        final minRun = (minVoicedRunMs / frameMs).ceil();
        _removeShortRuns(voiced, true, minRun);
      }
    }
    final active = List<bool>.of(voiced);
    _fillInnerGaps(active, (bridgeMs / frameMs).ceil());
    return FrameAnalysis(frameMs, db, voiced, active, threshold);
  }

  /// Computes all metrics from a [FrameAnalysis].
  DeliveryMetrics metrics(
    FrameAnalysis fa,
    Float32List samples,
    int sampleRate,
    Transcript transcript,
  ) {
    final durationS = sampleRate > 0 ? samples.length / sampleRate : 0.0;
    final frameS = fa.frameMs / 1000.0;

    // Speaking span and pauses (leading/trailing silence ignored).
    final first = fa.firstActive, last = fa.lastActive;
    var pauses = 0;
    var longestPause = 0.0;
    var activeFrames = 0;
    if (first >= 0) {
      var gap = 0;
      for (var f = first; f <= last; f++) {
        if (fa.active[f]) {
          activeFrames++;
          if (gap > 0) {
            final s = gap * frameS;
            if (s > pauseS) pauses++;
            if (s > longestPause) longestPause = s;
            gap = 0;
          }
        } else {
          gap++;
        }
      }
    }
    final spanFrames = first >= 0 ? last - first + 1 : 0;
    final speechRatio = spanFrames > 0 ? activeFrames / spanFrames : 0.0;

    // Words and rate over the speaking span.
    final words = transcript.words.isNotEmpty ? transcript.words.length : countWords(transcript.text);
    var spanS = spanFrames * frameS;
    if (spanS <= 0 && transcript.words.isNotEmpty) {
      spanS = (transcript.words.last.endMs - transcript.words.first.startMs) / 1000.0;
    }
    if (spanS <= 0) spanS = durationS;
    final wpm = (words > 0 && spanS > 0) ? (words / (spanS / 60.0)).round() : 0;

    // Fillers.
    final fillers = countFillers(transcript.text);
    final fillerCount = fillers.values.fold<int>(0, (a, b) => a + b);

    // Loudness over voiced frames.
    final voicedDb = <double>[
      for (var f = 0; f < fa.length; f++)
        if (fa.voiced[f]) fa.db[f],
    ];
    final loudMean = voicedDb.isEmpty ? -100.0 : _mean(voicedDb);
    final loudSd = voicedDb.length < 2 ? 0.0 : _sd(voicedDb, loudMean);

    // Trailing off: last 20% of voiced frames vs the rest.
    var trailingOff = false;
    if (voicedDb.length >= 10) {
      final cut = (voicedDb.length * 0.8).floor();
      final head = voicedDb.sublist(0, cut), tail = voicedDb.sublist(cut);
      trailingOff = _mean(head) - _mean(tail) >= trailingOffDb;
    }

    // Pitch.
    final voicedS = voicedDb.length * frameS;
    final pitches = pitchTrack(samples, sampleRate, fa);
    double? pitchMean, pitchSd;
    bool? monotone;
    if (pitches.length >= 20) {
      pitchMean = _mean(pitches);
      final st = [for (final p in pitches) 12 * math.log(p / pitchMean) / math.ln2];
      pitchSd = _sd(st, _mean(st));
      if (voicedS >= monotoneMinVoicedS) monotone = pitchSd < monotoneSemitones;
    }

    return DeliveryMetrics(
      durationS: durationS,
      words: words,
      wpm: wpm,
      pausesOver1s: pauses,
      longestPauseS: longestPause,
      fillerCount: fillerCount,
      fillers: fillers,
      loudnessDbMean: loudMean,
      loudnessDbSd: loudSd,
      trailingOff: trailingOff,
      pitchHzMean: pitchMean,
      pitchSemitoneSd: pitchSd,
      monotone: monotone,
      speechRatio: speechRatio,
    );
  }

  /// F0 (Hz) for voiced frames, median-smoothed within voiced runs, with
  /// octave-jump outliers (> 10 semitones from the median) removed.
  List<double> pitchTrack(Float32List samples, int sampleRate, FrameAnalysis fa) {
    // Work at <= ~24 kHz: box-filter decimation keeps YIN cheap for 44.1/48 kHz.
    var x = samples;
    var sr = sampleRate;
    final factor = sampleRate ~/ 16000;
    if (factor >= 2) {
      final n = samples.length ~/ factor;
      final y = Float32List(n);
      for (var i = 0; i < n; i++) {
        var s = 0.0;
        for (var k = 0; k < factor; k++) {
          s += samples[i * factor + k];
        }
        y[i] = s / factor;
      }
      x = y;
      sr = sampleRate ~/ factor;
    }
    final frameLen = sr * fa.frameMs ~/ 1000;
    final tauMin = (sr / maxPitchHz).floor();
    final tauMax = (sr / minPitchHz).ceil();
    final d = Float64List(tauMax + 2);
    final cmnd = Float64List(tauMax + 2);

    final runs = <List<double>>[];
    List<double>? run;
    for (var f = 0; f < fa.length; f++) {
      final start = f * frameLen;
      double? p;
      if (fa.voiced[f] && start + frameLen + tauMax + 1 <= x.length) {
        p = _yin(x, start, frameLen, tauMin, tauMax, sr, d, cmnd);
      }
      if (p != null) {
        (run ??= <double>[]).add(p);
      } else if (run != null) {
        runs.add(run);
        run = null;
      }
    }
    if (run != null) runs.add(run);

    final smoothed = <double>[];
    for (final r in runs) {
      for (var i = 0; i < r.length; i++) {
        if (r.length < 3 || i == 0 || i == r.length - 1) {
          smoothed.add(r[i]);
        } else {
          final a = r[i - 1], b = r[i], c = r[i + 1];
          smoothed.add(math.max(math.min(a, b), math.min(math.max(a, b), c)));
        }
      }
    }
    if (smoothed.isEmpty) return smoothed;
    final sorted = List<double>.of(smoothed)..sort();
    final median = sorted[sorted.length ~/ 2];
    return [
      for (final p in smoothed)
        if ((12 * math.log(p / median) / math.ln2).abs() <= 10) p,
    ];
  }

  double? _yin(Float32List x, int start, int w, int tauMin, int tauMax, int sr, Float64List d,
      Float64List cmnd) {
    for (var tau = 1; tau <= tauMax + 1; tau++) {
      var s = 0.0;
      for (var j = 0; j < w; j++) {
        final diff = x[start + j] - x[start + j + tau];
        s += diff * diff;
      }
      d[tau] = s;
    }
    cmnd[0] = 1;
    var running = 0.0;
    for (var tau = 1; tau <= tauMax + 1; tau++) {
      running += d[tau];
      cmnd[tau] = running > 0 ? d[tau] * tau / running : 1.0;
    }
    var best = -1;
    for (var tau = tauMin; tau <= tauMax; tau++) {
      if (cmnd[tau] < yinThreshold) {
        while (tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau]) {
          tau++;
        }
        best = tau;
        break;
      }
    }
    if (best < 0) return null;
    var tauF = best.toDouble();
    if (best > 1) {
      final a = cmnd[best - 1], b = cmnd[best], c = cmnd[best + 1];
      final denom = a + c - 2 * b;
      if (denom.abs() > 1e-12) tauF = best + 0.5 * (a - c) / denom;
    }
    final f0 = sr / tauF;
    if (f0 < minPitchHz || f0 > maxPitchHz) return null;
    return f0;
  }

  /// Replaces provisional word ends with the end of voicing after the word's
  /// start (never past the next word's start, at most 1.5 s per word).
  List<TimedWord> refineWordEnds(List<TimedWord> words, FrameAnalysis fa) {
    if (fa.length == 0) return words;
    final out = <TimedWord>[];
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final nextStart = i + 1 < words.length ? words[i + 1].startMs : null;
      final limit = math.min(nextStart ?? (fa.length * fa.frameMs), w.startMs + 1500);
      // Walk forward from the provisional end while frames stay voiced, or
      // pull back to the last voiced frame (not before the last token start).
      var f = (w.endMs ~/ fa.frameMs).clamp(0, fa.length - 1);
      var endMs = w.endMs;
      if (fa.voiced[f]) {
        while (f < fa.length && fa.voiced[f] && (f + 1) * fa.frameMs <= limit) {
          endMs = (f + 1) * fa.frameMs;
          f++;
        }
      } else {
        final floorMs = math.max(w.startMs + 80, w.endMs - 250);
        while (f > 0 && !fa.voiced[f] && f * fa.frameMs > floorMs) {
          f--;
        }
        endMs = math.max(floorMs, math.min(w.endMs, (f + 1) * fa.frameMs));
      }
      if (endMs > limit) endMs = limit;
      if (endMs <= w.startMs) endMs = w.startMs + 1;
      out.add(TimedWord(w.text, w.startMs, endMs));
    }
    return out;
  }
}

double _percentile(Float64List sorted, double q) {
  if (sorted.isEmpty) return -100;
  final i = ((sorted.length - 1) * q).round();
  return sorted[i];
}

double _mean(List<double> v) => v.fold<double>(0, (a, b) => a + b) / v.length;

double _sd(List<double> v, double mean) {
  var s = 0.0;
  for (final x in v) {
    s += (x - mean) * (x - mean);
  }
  return math.sqrt(s / v.length);
}

void _removeShortRuns(List<bool> m, bool value, int minLen) {
  var i = 0;
  while (i < m.length) {
    if (m[i] != value) {
      i++;
      continue;
    }
    var j = i;
    while (j < m.length && m[j] == value) {
      j++;
    }
    if (j - i < minLen) {
      for (var k = i; k < j; k++) {
        m[k] = !value;
      }
    }
    i = j;
  }
}

void _fillInnerGaps(List<bool> m, int maxGap) {
  final first = m.indexOf(true), last = m.lastIndexOf(true);
  if (first < 0) return;
  var i = first;
  while (i <= last) {
    if (m[i]) {
      i++;
      continue;
    }
    var j = i;
    while (j <= last && !m[j]) {
      j++;
    }
    if (j - i < maxGap) {
      for (var k = i; k < j; k++) {
        m[k] = true;
      }
    }
    i = j;
  }
}
