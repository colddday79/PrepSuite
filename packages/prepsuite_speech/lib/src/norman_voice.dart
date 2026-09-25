import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'speech_models.dart';
import 'tts_worker.dart';
import 'types.dart';

class _Chunk {
  final String path;
  final int durationMs;
  final Float32List envelope;
  const _Chunk(this.path, this.durationMs, this.envelope);
}

/// The interviewer voice: Piper "Norman" (en_US, medium) synthesised offline
/// in a background isolate, one sentence at a time, and played as it is
/// ready. [speak] completes when the last sentence has played or [stop] is
/// called; it throws if the voice cannot be loaded or synthesis fails.
class NormanVoice implements InterviewerVoice {
  NormanVoice({this.models, this.speed = 1.0, this.numThreads = 2}) {
    _completeSub = _player.onPlayerComplete.listen((_) => _completeChunk());
  }

  /// Model paths; null means [SpeechModels.ensureReady] is used.
  final SpeechModelPaths? models;

  /// Speaking rate (1.0 = the voice's natural rate).
  final double speed;
  final int numThreads;

  static final AudioContext _audioContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
      },
    ),
  );

  // A fixed playerId survives a hot restart on the native side and the new
  // player never hears its completion events, so let the plugin pick one.
  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<void> _completeSub;
  final _level = StreamController<double>.broadcast();

  Isolate? _isolate;
  ReceivePort? _inbox;
  Future<SendPort>? _worker;
  String? _outDir;

  int _utterance = 0;
  final _chunks = <int, StreamController<_Chunk>>{};
  Completer<void>? _chunkDone;
  Timer? _meter;
  double _smoothed = 0;

  @override
  Stream<double> get level => _level.stream;

  /// Loads the voice now (otherwise the first [speak] does it, ~1 s).
  Future<void> warmUp() async {
    await _ensureWorker();
  }

  Future<SendPort> _ensureWorker() => _worker ??= _spawn().catchError((Object e) {
        _worker = null;
        throw e;
      });

  Future<SendPort> _spawn() async {
    final paths = models ?? await SpeechModels.ensureReady();
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/prepsuite_speech/tts');
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    _outDir = dir.path;
    final inbox = ReceivePort();
    final ready = Completer<SendPort>();
    inbox.listen((dynamic msg) {
      final m = msg as List<Object?>;
      switch (m[0]) {
        case 'ready':
          ready.complete(m[1] as SendPort);
        case 'error':
          if (!ready.isCompleted) ready.completeError(StateError(m[1] as String));
        case 'chunk':
          final c = _chunks[m[1] as int];
          final chunk = _Chunk(m[2] as String, m[3] as int, m[4] as Float32List);
          if (c == null) {
            _delete(chunk.path);
          } else {
            c.add(chunk);
          }
        case 'done':
          _chunks.remove(m[1] as int)?.close();
        case 'failed':
          final c = _chunks.remove(m[1] as int);
          c?.addError(StateError('Norman voice failed: ${m[2]}'));
          c?.close();
      }
    });
    _inbox = inbox;
    _isolate = await Isolate.spawn(
      ttsWorkerMain,
      <Object?>[
        inbox.sendPort,
        <String, Object?>{...paths.toMap(), 'threads': numThreads},
      ],
      debugName: 'prepsuite_tts',
    );
    return ready.future;
  }

  @override
  Future<void> speak(String text) async {
    await stop();
    final clean = text.trim();
    if (clean.isEmpty) return;
    final id = ++_utterance;
    final port = await _ensureWorker();
    if (id != _utterance) return; // stopped while loading
    final chunks = StreamController<_Chunk>();
    _chunks[id] = chunks;
    port.send(['speak', id, clean, _outDir!, speed]);
    try {
      await for (final c in chunks.stream) {
        if (id != _utterance) {
          _delete(c.path);
          continue;
        }
        await _play(c, id);
        _delete(c.path);
      }
    } finally {
      _chunks.remove(id);
      if (id == _utterance) _setLevel(0);
    }
  }

  Future<void> _play(_Chunk c, int id) async {
    final done = Completer<void>();
    _chunkDone = done;
    // A stuck audio path must not hold the interview on "speaking" forever.
    await _player
        .play(DeviceFileSource(c.path, mimeType: 'audio/wav'), ctx: _audioContext)
        .timeout(const Duration(seconds: 8), onTimeout: () => throw StateError('Norman voice did not start playing'));
    if (id != _utterance) {
      await _player.stop(); // stop() raced with play()
      return;
    }
    final clock = Stopwatch()..start();
    _meter?.cancel();
    _meter = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final i = clock.elapsedMilliseconds ~/ envelopeMs;
      final target = i < c.envelope.length ? c.envelope[i] : 0.0;
      _smoothed += (target - _smoothed) * (target > _smoothed ? 0.6 : 0.25);
      _level.add(_smoothed);
    });
    // Fallback in case the completion event is lost (e.g. focus change).
    final fallback = Timer(Duration(milliseconds: c.durationMs + 1500), () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    fallback.cancel();
    _meter?.cancel();
    _meter = null;
  }

  void _completeChunk() {
    final d = _chunkDone;
    _chunkDone = null;
    if (d != null && !d.isCompleted) d.complete();
  }

  void _setLevel(double v) {
    _smoothed = v;
    if (!_level.isClosed) _level.add(v);
  }

  static void _delete(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _utterance++;
    for (final c in _chunks.values) {
      c.close();
    }
    _chunks.clear();
    _meter?.cancel();
    _meter = null;
    _completeChunk();
    try {
      await _player.stop();
    } catch (_) {}
    _setLevel(0);
  }

  /// Stops speech and releases the player and the voice isolate.
  Future<void> dispose() async {
    await stop();
    await _completeSub.cancel();
    final w = _worker;
    if (w != null) {
      try {
        (await w).send(['close']);
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _inbox?.close();
    await _player.dispose();
    await _level.close();
  }
}
