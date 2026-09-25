import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'asr_worker.dart';
import 'speech_models.dart';
import 'types.dart';

/// Offline [SpeechCapture]: one microphone stream (PCM16, 16 kHz, mono) feeds
/// the recogniser and the WAV file in a background isolate.
///
/// Recordings go to `<app support>/prepsuite_speech/recordings/` unless
/// [recordingsDir] is given. The microphone permission is requested by
/// [start] (the app must declare it: RECORD_AUDIO / NSMicrophoneUsageDescription).
class OfflineSpeechCapture implements SpeechCapture {
  OfflineSpeechCapture({
    this.models,
    this.recordingsDir,
    this.numThreads = 2,
    AudioRecorder? recorder,
    @visibleForTesting void Function(List<Object?>)? workerMain,
  }) : _recorder = recorder ?? AudioRecorder(),
       _workerMain = workerMain ?? asrWorkerMain;

  /// Model paths; null means [SpeechModels.ensureReady] is used.
  final SpeechModelPaths? models;
  final String? recordingsDir;
  final int numThreads;
  final AudioRecorder _recorder;
  final void Function(List<Object?>) _workerMain;

  /// Called when a recording stops by itself at `maxDuration`; the result is
  /// then available from [stop].
  void Function()? onMaxDuration;

  final _level = StreamController<double>.broadcast();
  final _partial = StreamController<String>.broadcast();

  Isolate? _isolate;
  ReceivePort? _inbox;
  Future<SendPort>? _worker;
  final _pending = <int, Completer<CaptureResult?>>{};
  int _nextId = 0;

  bool _recording = false;
  Future<bool>? _starting;
  Future<void>? _cancelling;
  bool _disposed = false;
  int _generation = 0;
  String? _recordingPath;
  StreamSubscription<Uint8List>? _mic;
  Completer<void>? _micDone;
  Timer? _guard;
  int _samples = 0;
  int _maxSamples = 0;
  int? _oddByte;
  double _smoothed = 0;
  Future<CaptureResult?>? _finishing;

  @override
  Stream<double> get level => _level.stream;

  @override
  Stream<String> get partialText => _partial.stream;

  /// True between a successful [start] and the end of recording.
  bool get isRecording => _recording;

  /// Loads the recogniser now (otherwise the first [start] does it, ~1 s).
  Future<void> warmUp() async {
    if (_disposed) throw StateError('Speech capture has been disposed.');
    await _ensureWorker();
  }

  Future<SendPort> _ensureWorker() => _worker ??= _spawn().catchError((Object e) {
        _worker = null;
        throw e;
      });

  Future<SendPort> _spawn() async {
    final paths = models ?? await SpeechModels.ensureReady();
    final inbox = ReceivePort();
    final ready = Completer<SendPort>();
    inbox.listen((dynamic msg) {
      if (msg == null || msg is! List || msg.isEmpty) {
        _workerFailed(ready, 'Speech recogniser stopped.');
        return;
      }
      final m = msg as List<Object?>;
      switch (m[0]) {
        case 'ready':
          ready.complete(m[1] as SendPort);
        case 'error':
          _workerFailed(ready, m[1] as String);
        case 'partial':
          if (_recording) _partial.add(m[1] as String);
        case 'result':
          _pending.remove(m[1] as int)?.complete(m[2] as CaptureResult?);
        case 'failed':
          _pending.remove(m[1] as int)?.complete(null);
        case 'log':
          // ignore: avoid_print
          print('prepsuite_speech: ${m[1]}');
        default:
          // Isolate uncaught errors arrive as [error text, stack text].
          _workerFailed(ready, 'Speech recogniser failed.');
      }
    });
    _inbox = inbox;
    _isolate = await Isolate.spawn(
      _workerMain,
      <Object?>[
        inbox.sendPort,
        <String, Object?>{...paths.toMap(), 'threads': numThreads},
      ],
      debugName: 'prepsuite_asr',
      onError: inbox.sendPort,
      onExit: inbox.sendPort,
    );
    try {
      return await ready.future;
    } catch (_) {
      _isolate?.kill(priority: Isolate.immediate);
      inbox.close();
      rethrow;
    }
  }

  void _workerFailed(Completer<SendPort> ready, String message) {
    if (!ready.isCompleted) ready.completeError(StateError(message));
    for (final request in _pending.values) {
      if (!request.isCompleted) request.complete(null);
    }
    _pending.clear();
    _worker = null;
  }

  Future<String> _newWavPath() async {
    final dir = recordingsDir ??
        '${(await getApplicationSupportDirectory()).path}/prepsuite_speech/recordings';
    return '$dir/answer_${DateTime.now().microsecondsSinceEpoch}.wav';
  }

  @override
  Future<bool> start({required Duration maxDuration}) async {
    if (_disposed || _recording || _starting != null || maxDuration <= Duration.zero) return false;
    final generation = ++_generation;
    final starting = _start(maxDuration, generation);
    _starting = starting;
    try {
      return await starting;
    } finally {
      if (identical(_starting, starting)) _starting = null;
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<bool> _start(Duration maxDuration, int generation) async {
    try {
      await _cancelling;
      if (!_isCurrent(generation)) return false;
      // A recording that stopped itself at maxDuration and was never
      // collected with stop() belongs to the preceding attempt. Discard it.
      final previous = _finishing;
      if (previous != null) {
        final uncollected = await previous;
        if (uncollected != null) await _deleteWav(uncollected.wavPath);
        if (identical(_finishing, previous)) _finishing = null;
      }
      if (!_isCurrent(generation)) return false;
      if (!await _recorder.hasPermission()) return false;
      if (!_isCurrent(generation)) return false;
      final port = await _ensureWorker();
      if (!_isCurrent(generation)) return false;
      final path = await _newWavPath();
      if (!_isCurrent(generation)) return false;
      _samples = 0;
      _maxSamples = maxDuration.inMilliseconds * asrSampleRate ~/ 1000;
      _oddByte = null;
      _smoothed = 0;
      port.send(['begin', path]);
      _recordingPath = path;
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: asrSampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        streamBufferSize: 1600,
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
      ));
      _recording = true;
      final micDone = _micDone = Completer<void>();
      _mic = stream.listen(
        (chunk) => _onPcm(chunk, port),
        onError: (Object _) => _autoStop(),
        onDone: () {
          if (!micDone.isCompleted) micDone.complete();
          _autoStop();
        },
      );
      if (!_isCurrent(generation)) {
        await _finish(keep: false);
        return false;
      }
      // Backup in case the microphone stops delivering audio.
      if (_finishing == null) {
        _guard = Timer(maxDuration + const Duration(seconds: 1), _autoStop);
      }
      return true;
    } catch (_) {
      // startStream can fail after the worker has opened a private WAV.
      // Close both sides before a retry can begin.
      if (_recordingPath != null) await _finish(keep: false);
      return false;
    }
  }

  void _onPcm(Uint8List chunk, SendPort port) {
    if (!_recording) return;
    var bytes = chunk;
    if (_oddByte != null) {
      bytes = Uint8List(chunk.length + 1)
        ..[0] = _oddByte!
        ..setRange(1, chunk.length + 1, chunk);
      _oddByte = null;
    }
    if (bytes.length.isOdd) {
      _oddByte = bytes.last;
      bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
    }
    var n = bytes.length ~/ 2;
    var reachedMax = false;
    if (_samples + n >= _maxSamples) {
      n = math.max(0, _maxSamples - _samples);
      bytes = Uint8List.sublistView(bytes, 0, n * 2);
      reachedMax = true;
    }
    if (n > 0) {
      final bd = ByteData.sublistView(bytes);
      var sum = 0.0;
      for (var i = 0; i < n; i++) {
        final v = bd.getInt16(i * 2, Endian.little) / 32768.0;
        sum += v * v;
      }
      final target = levelFromRms(math.sqrt(sum / n));
      _smoothed += (target - _smoothed) * (target > _smoothed ? 0.6 : 0.2);
      _level.add(_smoothed);
      _samples += n;
      port.send(['pcm', TransferableTypedData.fromList([bytes])]);
    }
    if (reachedMax) _autoStop();
  }

  void _autoStop() {
    if (!_recording || _finishing != null) return;
    _finish(keep: true);
    onMaxDuration?.call();
  }

  Future<CaptureResult?> _finish({required bool keep}) {
    final existing = _finishing;
    if (existing != null) return existing;
    // Publish the finishing future before stop() can synchronously close its
    // stream and re-enter _autoStop().
    final done = Completer<CaptureResult?>();
    _finishing = done.future;
    () async {
      final path = _recordingPath;
      _guard?.cancel();
      _guard = null;
      // Stop the recorder first and let the stream flush its last buffer so
      // the end of the final word is kept (bounded wait).
      try {
        await _recorder.stop();
      } catch (_) {}
      await _micDone?.future.timeout(const Duration(milliseconds: 600), onTimeout: () {});
      _recording = false;
      try {
        await _mic?.cancel();
      } catch (_) {}
      _mic = null;
      _micDone = null;
      _smoothed = 0;
      _level.add(0);
      CaptureResult? result;
      try {
        final port = await _ensureWorker();
        final id = ++_nextId;
        final reply = Completer<CaptureResult?>();
        _pending[id] = reply;
        port.send(['end', id, keep]);
        result = await reply.future;
      } catch (_) {
        // A native/model failure is reported as no result, never invented text.
      }
      if (!keep || result == null) {
        if (path != null) await _deleteWav(path);
      }
      _recordingPath = null;
      done.complete(result);
    }();
    return done.future;
  }

  @override
  Future<CaptureResult?> stop() async {
    final generation = _generation;
    final starting = _starting;
    if (starting != null && !await starting) return null;
    if (!_isCurrent(generation)) return null;
    if (!_recording && _finishing == null) return null;
    final f = _finish(keep: true);
    try {
      final result = await f;
      if (!_isCurrent(generation)) {
        if (result != null) await _deleteWav(result.wavPath);
        return null;
      }
      return result;
    } finally {
      if (identical(_finishing, f)) _finishing = null;
    }
  }

  @override
  Future<void> cancel() {
    _generation++;
    final starting = _starting;
    final previous = _cancelling;
    final cancelling = () async {
      await previous;
      await starting;
      if (!_recording && _finishing == null) return;
      final f = _finish(keep: false);
      try {
        // Non-null if automatic stop was already keeping the audio.
        final kept = await f;
        if (kept != null) await _deleteWav(kept.wavPath);
      } finally {
        if (identical(_finishing, f)) _finishing = null;
      }
    }();
    _cancelling = cancelling;
    return cancelling.whenComplete(() {
      if (identical(_cancelling, cancelling)) _cancelling = null;
    });
  }

  @override
  Future<CaptureResult?> transcribeFile(String wavPath) async {
    if (_disposed) return null;
    final SendPort port;
    try {
      port = await _ensureWorker();
    } catch (_) {
      return null;
    }
    if (_disposed) return null;
    final id = ++_nextId;
    final done = Completer<CaptureResult?>();
    _pending[id] = done;
    port.send(['file', id, wavPath]);
    return done.future;
  }

  /// Releases the microphone, the recogniser and the isolate.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel();
    final w = _worker;
    if (w != null) {
      try {
        (await w).send(['close']);
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _inbox?.close();
    for (final c in _pending.values) {
      c.complete(null);
    }
    _pending.clear();
    await _recorder.dispose();
    await _level.close();
    await _partial.close();
  }
}

Future<void> _deleteWav(String path) async {
  try {
    final wav = File(path);
    if (await wav.exists()) await wav.delete();
  } on FileSystemException catch (_) {
    // Retry is safe if cancellation and result consumption race to delete it.
  }
}
