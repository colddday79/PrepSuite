// Named constructor parameters stay public; the fields are private.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:prepsuite_speech/prepsuite_speech.dart' show SpeechModels, SpeechModelsMissing;

import 'contracts.dart';

enum SpeechLoadPhase { idle, loading, ready, failed }

/// Where the offline speech engine is. No microphone audio is captured while
/// the bundled models are being copied or opened.
@immutable
class SpeechReadiness {
  const SpeechReadiness(
    this.phase, {
    this.progress = 0,
    this.copying = false,
    this.missing = false,
    this.error,
  });

  static const ready = SpeechReadiness(SpeechLoadPhase.ready, progress: 1);

  final SpeechLoadPhase phase;

  /// 0..1 while [copying].
  final double progress;

  /// First launch only: the model files are being copied onto the phone.
  final bool copying;

  /// This build has no model files, so voice will never work: type instead.
  final bool missing;

  /// Plain-words reason when [phase] is failed.
  final String? error;

  bool get isReady => phase == SpeechLoadPhase.ready;
  bool get isFailed => phase == SpeechLoadPhase.failed;
}

/// Gets the offline models onto the phone and loads the recogniser and the
/// interviewer voice. Started once at app launch; screens show [state] if they
/// open before it is done. [prepare] can be called again after a failure.
class SpeechSetup {
  SpeechSetup({
    Future<void> Function(void Function(double progress))? prepareModels,
    Future<void> Function()? warmUpCapture,
    Future<void> Function()? warmUpVoice,
  }) : _prepareModels = prepareModels ?? _bundledModels,
       _warmUpCapture = warmUpCapture,
       _warmUpVoice = warmUpVoice,
       _state = ValueNotifier(const SpeechReadiness(SpeechLoadPhase.idle));

  /// Nothing to prepare (demo speech and tests).
  SpeechSetup.ready()
    : _prepareModels = null,
      _warmUpCapture = null,
      _warmUpVoice = null,
      _state = ValueNotifier(SpeechReadiness.ready);

  static const missingMessage =
      "Voice isn't in this build: the offline speech files are missing. You can type instead.";
  static const failedMessage =
      "Voice couldn't start on this phone. You can type instead.";

  final Future<void> Function(void Function(double))? _prepareModels;
  final Future<void> Function()? _warmUpCapture;
  final Future<void> Function()? _warmUpVoice;
  final ValueNotifier<SpeechReadiness> _state;
  Future<void>? _pending;

  ValueListenable<SpeechReadiness> get state => _state;

  static Future<void> _bundledModels(void Function(double) progress) async {
    await SpeechModels.ensureReady(onProgress: progress);
  }

  /// Completes when speech is ready; throws when it cannot be (see [state]).
  Future<void> prepare() {
    if (_state.value.isReady) return Future.value();
    return _pending ??= _run().whenComplete(() => _pending = null);
  }

  Future<void> _run() async {
    final clock = Stopwatch()..start();
    _state.value = const SpeechReadiness(SpeechLoadPhase.loading);
    try {
      await _prepareModels!((p) {
        // Progress below 1 means files are being copied (first launch only).
        if (p < 1) {
          _state.value = SpeechReadiness(SpeechLoadPhase.loading, progress: p.clamp(0.0, 1.0), copying: true);
        }
      });
      _state.value = const SpeechReadiness(SpeechLoadPhase.loading, progress: 1);
      // The recogniser is required; the voice is optional (questions stay on screen).
      await Future.wait([
        if (_warmUpCapture != null) _warmUpCapture(),
        if (_warmUpVoice != null)
          _warmUpVoice().catchError((Object e) => debugPrint('PrepSuite: interviewer voice unavailable: $e')),
      ]);
      _state.value = SpeechReadiness.ready;
      debugPrint('PrepSuite: offline speech ready in ${clock.elapsedMilliseconds} ms');
    } on SpeechModelsMissing catch (e) {
      debugPrint('PrepSuite: $e');
      _state.value = const SpeechReadiness(SpeechLoadPhase.failed, missing: true, error: missingMessage);
      rethrow;
    } catch (e) {
      debugPrint('PrepSuite: offline speech failed to start: $e');
      _state.value = const SpeechReadiness(SpeechLoadPhase.failed, error: failedMessage);
      rethrow;
    }
  }
}

/// Wraps the on-device capture (`OfflineSpeechCapture`) for the screens: waits
/// for [SpeechSetup], explains failures in plain words, never leaves a hidden
/// microphone open, and deletes each recording once it has been transcribed.
class SpeechCaptureAdapter implements SpeechCapture {
  SpeechCaptureAdapter({required SpeechCapture capture, required SpeechSetup setup})
    : _capture = capture,
      _setup = setup;

  final SpeechCapture _capture;
  final SpeechSetup _setup;
  Future<bool>? _starting;
  Future<void>? _cancelling;
  int _generation = 0;
  bool _disposed = false;
  String? _lastError;

  String? get lastError => _lastError;

  @override
  Stream<double> get level => _capture.level;

  @override
  Stream<String> get partialText => _capture.partialText;

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
      // Let the previous screen's cleanup finish before opening a new recording.
      await _cancelling;
      await _setup.prepare();
      if (_disposed || generation != _generation) return false;
      final started = await _capture.start(maxDuration: maxDuration);
      if (_disposed || generation != _generation) {
        if (started) await _capture.cancel();
        return false;
      }
      if (!started) {
        _lastError =
            'The microphone could not start. Check microphone access, then try again or type your answer.';
      }
      return started;
    } catch (error) {
      _lastError ??= _setup.state.value.error ?? 'Voice input could not start. Try again, or type your answer.';
      debugPrint('PrepSuite: voice input failed to start: $error');
      return false;
    }
  }

  @override
  Future<CaptureResult?> stop() async {
    final generation = _generation;
    final starting = _starting;
    if (starting != null && !await starting) return null;
    CaptureResult? result;
    try {
      result = await _capture.stop();
    } catch (error) {
      debugPrint('PrepSuite: transcription failed: $error');
    }
    if (result == null) {
      _lastError = 'That recording could not be transcribed. Try again or type your answer.';
      return null;
    }
    // Only the transcript and the measurements are needed: remove the private
    // WAV now instead of keeping interview audio on the phone.
    await _deleteRecording(result.wavPath);
    if (_disposed || generation != _generation) return null;
    _lastError = null;
    if (kDebugMode) {
      debugPrint(
        'PrepSuite heard (${result.durationMs} ms, peak ${result.peakLevel.toStringAsFixed(2)}): '
        '"${result.transcript.text}"\nPrepSuite delivery: ${result.metrics.toJson()}',
      );
    }
    return CaptureResult('', result.durationMs, result.transcript, result.metrics, result.peakLevel);
  }

  @override
  Future<void> cancel() {
    _generation++;
    final starting = _starting;
    final previous = _cancelling;
    final cancelling = () async {
      await previous;
      // A start may still be in flight; its generation check cancels it, so
      // no microphone is left open behind the screen.
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
      await _setup.prepare();
      return await _capture.transcribeFile(wavPath);
    } catch (_) {
      _lastError ??= 'That audio file could not be transcribed.';
      return null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel();
  }
}

/// Readable error detail for the screens; null for test doubles.
String? speechErrorMessage(SpeechCapture capture) =>
    capture is SpeechCaptureAdapter ? capture.lastError : null;

Future<void> _deleteRecording(String path) async {
  if (path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on FileSystemException catch (error) {
    debugPrint('PrepSuite could not remove a temporary recording: ${error.osError}');
  }
}

/// The interviewer's voice (Norman). Throws from [speak] when voice is not
/// available so the screens keep the question on screen to read.
class InterviewerVoiceAdapter implements InterviewerVoice {
  InterviewerVoiceAdapter({required InterviewerVoice voice, required SpeechSetup setup})
    : _voice = voice,
      _setup = setup;

  final InterviewerVoice _voice;
  final SpeechSetup _setup;

  @override
  Stream<double> get level => _voice.level;

  @override
  Future<void> speak(String text) async {
    final setup = _setup.state.value;
    if (setup.isFailed) throw StateError(setup.error ?? SpeechSetup.failedMessage);
    if (!kDebugMode) return _voice.speak(text);
    // Debug builds log each line with its loudest output level, so a run on a
    // device or emulator shows that Norman actually played.
    final clock = Stopwatch()..start();
    var peak = 0.0;
    final sub = _voice.level.listen((v) => peak = v > peak ? v : peak);
    try {
      await _voice.speak(text);
      debugPrint(
        'PrepSuite voice: played "${text.length > 48 ? '${text.substring(0, 48)}…' : text}" '
        'in ${clock.elapsedMilliseconds} ms, peak level ${peak.toStringAsFixed(2)}',
      );
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<void> stop() => _voice.stop();
}

/// No read-aloud and no animated levels (INTERVIEWER_VOICE=none).
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
