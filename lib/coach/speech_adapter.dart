import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:prepsuite_speech/prepsuite_speech.dart' as native;

import 'contracts.dart';

enum SpeechLoadPhase { idle, loading, ready, failed }

/// Preparation is separate from recording: no microphone audio is captured
/// while the bundled offline model is being copied or opened.
@immutable
class SpeechReadiness {
  const SpeechReadiness(this.phase, {this.progress = 0, this.error});

  final SpeechLoadPhase phase;
  final double progress;
  final String? error;
}

/// Bridges the independently versioned speech package into the coach contract.
/// Normal builds use actual microphone samples and on-device transcripts.
class SpeechCaptureAdapter implements SpeechCapture {
  SpeechCaptureAdapter({
    native.SpeechCapture? capture,
    Future<void> Function(void Function(double))? prepareModels,
  }) : _capture = capture ?? native.OfflineSpeechCapture(),
       _prepareModels = prepareModels ?? _prepareBundledModels;

  final native.SpeechCapture _capture;
  final Future<void> Function(void Function(double)) _prepareModels;
  final _readiness = ValueNotifier(const SpeechReadiness(SpeechLoadPhase.idle));
  Future<void>? _preparing;
  Future<bool>? _starting;
  Future<void>? _cancelling;
  int _generation = 0;
  bool _disposed = false;
  String? _lastError;

  ValueListenable<SpeechReadiness> get readiness => _readiness;
  String? get lastError => _lastError;

  @override
  Stream<double> get level => _capture.level;

  @override
  Stream<String> get partialText => _capture.partialText;

  static Future<void> _prepareBundledModels(
    void Function(double) progress,
  ) async {
    await native.SpeechModels.ensureReady(onProgress: progress);
  }

  Future<void> prepare() {
    if (_disposed) return Future.error(StateError('Speech input is closed.'));
    if (_readiness.value.phase == SpeechLoadPhase.ready) return Future.value();
    return _preparing ??= _prepare();
  }

  Future<void> _prepare() async {
    _lastError = null;
    _readiness.value = const SpeechReadiness(SpeechLoadPhase.loading);
    try {
      await _prepareModels((progress) {
        if (!_disposed) {
          _readiness.value = SpeechReadiness(
            SpeechLoadPhase.loading,
            progress: progress.clamp(0, 1),
          );
        }
      });
      if (_capture case final native.OfflineSpeechCapture capture) {
        await capture.warmUp();
      }
      if (!_disposed) {
        _readiness.value = const SpeechReadiness(
          SpeechLoadPhase.ready,
          progress: 1,
        );
      }
    } catch (error) {
      _lastError = error is native.SpeechModelsMissing
          ? 'The offline speech files are missing from this build. You can still type your answer.'
          : 'Voice input could not start on this device. Try again, or type your answer.';
      if (!_disposed) {
        _readiness.value = SpeechReadiness(
          SpeechLoadPhase.failed,
          error: _lastError,
        );
      }
      // Keep native diagnostics in development logs, never substitute a sample
      // transcript when model preparation fails.
      debugPrint('PrepSuite speech preparation failed: $error');
      rethrow;
    } finally {
      _preparing = null;
    }
  }

  @override
  Future<bool> start({required Duration maxDuration}) async {
    if (_disposed || _starting != null) return false;
    if (maxDuration <= Duration.zero) {
      _lastError = 'Recording duration must be greater than zero.';
      return false;
    }
    final generation = ++_generation;
    final starting = _start(maxDuration, generation);
    _starting = starting;
    try {
      return await starting;
    } finally {
      if (identical(_starting, starting)) _starting = null;
    }
  }

  Future<bool> _start(Duration maxDuration, int generation) async {
    _lastError = null;
    try {
      // Await cleanup of the preceding screen before opening a new recording.
      await _cancelling;
      await prepare();
      if (_disposed || generation != _generation) return false;
      final started = await _capture.start(maxDuration: maxDuration);
      if (_disposed || generation != _generation) {
        await _capture.cancel();
        return false;
      }
      if (!started) {
        _lastError = 'The microphone could not start. Check microphone access, then try again or type your answer.';
      }
      return started;
    } catch (error) {
      _lastError ??=
          'Voice input could not start. Try again, or type your answer.';
      debugPrint('PrepSuite voice input failed to start: $error');
      return false;
    }
  }

  @override
  Future<CaptureResult?> stop() async {
    final generation = _generation;
    final starting = _starting;
    if (starting != null && !await starting) return null;
    final result = await _capture.stop();
    if (result == null) {
      _lastError = 'That recording could not be transcribed. Try again or type your answer.';
      return null;
    }
    // The app needs the transcript and measurements only. Remove the private
    // WAV immediately instead of keeping unneeded interview audio on the phone.
    await _deleteRecording(result.wavPath);
    if (_disposed || generation != _generation) return null;
    _lastError = null;
    return _mapResult(result, keepAudioPath: false);
  }

  @override
  Future<void> cancel() {
    _generation++;
    final starting = _starting;
    final previous = _cancelling;
    final cancelling = () async {
      await previous;
      // A microphone start may already be in flight. Its generation check
      // cancels it before this method completes; never leave a hidden mic open.
      await starting;
      await _capture.cancel();
    }();
    _cancelling = cancelling;
    return cancelling.whenComplete(() {
      if (identical(_cancelling, cancelling)) _cancelling = null;
    });
  }

  @override
  Future<CaptureResult?> transcribeFile(String wavPath) async {
    try {
      await prepare();
      final result = await _capture.transcribeFile(wavPath);
      return result == null ? null : _mapResult(result);
    } catch (_) {
      _lastError ??= 'That audio file could not be transcribed.';
      return null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel();
    if (_capture case final native.OfflineSpeechCapture capture) {
      await capture.dispose();
    }
    _readiness.dispose();
  }
}

/// Readable error detail without requiring test doubles to implement native
/// model readiness. Returns null when the supplied capture is a test double.
String? speechErrorMessage(SpeechCapture capture) =>
    capture is SpeechCaptureAdapter ? capture.lastError : null;

Future<void> _deleteRecording(String path) async {
  if (path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on FileSystemException catch (error) {
    debugPrint(
      'PrepSuite could not remove temporary recording: ${error.osError}',
    );
  }
}

CaptureResult _mapResult(
  native.CaptureResult result, {
  bool keepAudioPath = true,
}) {
  final m = result.metrics;
  return CaptureResult(
    keepAudioPath ? result.wavPath : '',
    result.durationMs,
    Transcript(
      result.transcript.text,
      List.unmodifiable([
        for (final word in result.transcript.words)
          TimedWord(word.text, word.startMs, word.endMs),
      ]),
      result.transcript.onDevice,
    ),
    DeliveryMetrics(
      durationS: m.durationS,
      words: m.words,
      wpm: m.wpm,
      pausesOver1s: m.pausesOver1s,
      longestPauseS: m.longestPauseS,
      fillerCount: m.fillerCount,
      fillers: Map.unmodifiable(m.fillers),
      loudnessDbMean: m.loudnessDbMean,
      loudnessDbSd: m.loudnessDbSd,
      trailingOff: m.trailingOff,
      pitchHzMean: m.pitchHzMean,
      pitchSemitoneSd: m.pitchSemitoneSd,
      monotone: m.monotone,
      speechRatio: m.speechRatio,
    ),
    result.peakLevel,
  );
}

/// Existing Norman is a replaceable local read-aloud option. Voice synthesis
/// errors propagate so the UI can keep the question visible for reading.
class InterviewerVoiceAdapter implements InterviewerVoice {
  InterviewerVoiceAdapter({native.InterviewerVoice? voice})
    : _voice = voice ?? native.NormanVoice();

  final native.InterviewerVoice _voice;

  @override
  Stream<double> get level => _voice.level;

  @override
  Future<void> speak(String text) => _voice.speak(text);

  @override
  Future<void> stop() => _voice.stop();

  Future<void> dispose() async {
    if (_voice case final native.NormanVoice voice) {
      await voice.dispose();
    } else {
      await _voice.stop();
    }
  }
}

/// No synthetic playback or animated audio levels when read-aloud is disabled.
class TextOnlyInterviewerVoice implements InterviewerVoice {
  @override
  Stream<double> get level => const Stream.empty();

  @override
  Future<void> speak(String text) async {
    throw StateError('Read-aloud is disabled. Read the question on screen.');
  }

  @override
  Future<void> stop() async {}
}
