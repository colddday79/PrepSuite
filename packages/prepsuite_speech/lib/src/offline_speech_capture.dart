import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

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
  }) : _recorder = recorder ?? AudioRecorder();

  /// Model paths; null means [SpeechModels.ensureReady] is used.
  final SpeechModelPaths? models;
  final String? recordingsDir;
  final int numThreads;
  final AudioRecorder _recorder;

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
  bool _starting = false;
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
      final m = msg as List<Object?>;
      switch (m[0]) {
        case 'ready':
          ready.complete(m[1] as SendPort);
        case 'error':
          if (!ready.isCompleted) ready.completeError(StateError(m[1] as String));
        case 'partial':
          if (_recording) _partial.add(m[1] as String);
        case 'result':
          _pending.remove(m[1] as int)?.complete(m[2] as CaptureResult?);
        case 'failed':
          _pending.remove(m[1] as int)?.complete(null);
        case 'log':
          // ignore: avoid_print
          print('prepsuite_speech: ${m[1]}');
      }
    });
    _inbox = inbox;
    _isolate = await Isolate.spawn(
      asrWorkerMain,
      <Object?>[
        inbox.sendPort,
        <String, Object?>{...paths.toMap(), 'threads': numThreads},
      ],
      debugName: 'prepsuite_asr',
    );
    return ready.future;
  }

  Future<String> _newWavPath() async {
    final dir = recordingsDir ??
        '${(await getApplicationSupportDirectory()).path}/prepsuite_speech/recordings';
    final now = DateTime.now();
    return '$dir/answer_${now.millisecondsSinceEpoch}.wav';
  }

  @override
  Future<bool> start({required Duration maxDuration}) async {
    if (_recording || _starting) return false;
    _starting = true;
    try {
      // A recording that stopped itself at maxDuration and was never
      // collected with stop() is finished (and kept on disk) first.
      final previous = _finishing;
      if (previous != null) {
        await previous;
        _finishing = null;
      }
      if (!await _recorder.hasPermission()) return false;
      final port = await _ensureWorker();
      final path = await _newWavPath();
      _samples = 0;
      _maxSamples = maxDuration.inMilliseconds * asrSampleRate ~/ 1000;
      _oddByte = null;
      _smoothed = 0;
      port.send(['begin', path]);
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
      // Backup in case the microphone stops delivering audio.
      _guard = Timer(maxDuration + const Duration(seconds: 1), _autoStop);
      return true;
    } catch (_) {
      _recording = false;
      return false;
    } finally {
      _starting = false;
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
    return _finishing = () async {
      _guard?.cancel();
      _guard = null;
      // Stop the recorder first and let the stream flush its last buffer so
      // the end of the final word is kept (bounded wait).
      try {
        await _recorder.stop();
      } catch (_) {}
      await _micDone?.future.timeout(const Duration(milliseconds: 600), onTimeout: () {});
      _recording = false;
      await _mic?.cancel();
      _mic = null;
      _smoothed = 0;
      _level.add(0);
      final port = await _ensureWorker();
      final id = ++_nextId;
      final done = Completer<CaptureResult?>();
      _pending[id] = done;
      port.send(['end', id, keep]);
      return done.future;
    }();
  }

  @override
  Future<CaptureResult?> stop() async {
    if (!_recording && _finishing == null) return null;
    final f = _finish(keep: true);
    try {
      return await f;
    } finally {
      if (identical(_finishing, f)) _finishing = null;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_recording && _finishing == null) return;
    final f = _recording ? _finish(keep: false) : _finishing!;
    try {
      // Non-null only if an automatic stop was already keeping the audio.
      final kept = await f;
      if (kept != null) {
        try {
          File(kept.wavPath).deleteSync();
        } catch (_) {}
      }
    } finally {
      if (identical(_finishing, f)) _finishing = null;
    }
  }

  @override
  Future<CaptureResult?> transcribeFile(String wavPath) async {
    final SendPort port;
    try {
      port = await _ensureWorker();
    } catch (_) {
      return null;
    }
    final id = ++_nextId;
    final done = Completer<CaptureResult?>();
    _pending[id] = done;
    port.send(['file', id, wavPath]);
    return done.future;
  }

  /// Releases the microphone, the recogniser and the isolate.
  Future<void> dispose() async {
    if (_recording) await cancel();
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
