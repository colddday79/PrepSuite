import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite_speech/prepsuite_speech.dart';
import 'package:record/record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory recordings;
  late _Recorder recorder;
  late OfflineSpeechCapture capture;
  setUp(() async {
    recordings = await Directory.systemTemp.createTemp('prepsuite_capture_');
    recorder = _Recorder();
    capture = OfflineSpeechCapture(
      models: const SpeechModelPaths('/unused-test-models'),
      recordingsDir: recordings.path,
      recorder: recorder,
      workerMain: _worker,
    );
  });
  tearDown(() async {
    await capture.dispose();
    await recordings.delete(recursive: true);
  });

  test('cancel during permission request prevents opening the microphone', () async {
    final permitted = Completer<bool>();
    recorder.permission = permitted.future;
    final start = capture.start(maxDuration: const Duration(seconds: 10));
    await recorder.permissionRequested.future;
    final cancel = capture.cancel();
    permitted.complete(true);
    expect(await start, isFalse);
    await cancel;
    expect(recorder.starts, 0);
    expect(capture.isRecording, isFalse);
  });

  test('cancel during microphone opening cleans up before a retry', () async {
    final opened = Completer<void>();
    recorder.openGate = opened.future;
    final start = capture.start(maxDuration: const Duration(seconds: 10));
    await recorder.openRequested.future;
    final cancel = capture.cancel();
    opened.complete();
    expect(await start, isFalse);
    await cancel;
    expect(capture.isRecording, isFalse);
    expect(recordings.listSync(), isEmpty);

    recorder.openGate = null;
    expect(await capture.start(maxDuration: const Duration(seconds: 10)), isTrue);
    expect(capture.isRecording, isTrue);
    await capture.cancel();
    expect(recordings.listSync(), isEmpty);
  });

  test('10 second sample limit trims oversized buffers and finishes once', () async {
    final result = Completer<CaptureResult?>();
    capture.onMaxDuration = () async { result.complete(await capture.stop()); };
    expect(await capture.start(maxDuration: const Duration(seconds: 10)), isTrue);
    recorder.add(Uint8List(16000 * 2 * 12));

    final recorded = await result.future.timeout(const Duration(seconds: 5));
    expect(recorded?.durationMs, 10000);
    expect(recorder.stops, 1);
    expect(capture.isRecording, isFalse);
    expect(File(recorded!.wavPath).lengthSync(), 16000 * 2 * 10);
    await File(recorded.wavPath).delete();
  });

  test('stop during microphone opening waits for this capture', () async {
    final opened = Completer<void>();
    recorder.openGate = opened.future;
    final start = capture.start(maxDuration: const Duration(seconds: 10));
    await recorder.openRequested.future;
    final stop = capture.stop();
    opened.complete();
    expect(await start, isTrue);
    final result = await stop.timeout(const Duration(seconds: 5));
    expect(result, isNotNull);
    expect(recorder.stops, 1);
    expect(capture.isRecording, isFalse);
    await File(result!.wavPath).delete();
  });

  test('a failed microphone start discards the opened private WAV', () async {
    recorder.failOpen = true;
    expect(await capture.start(maxDuration: const Duration(seconds: 10)), isFalse);
    expect(recordings.listSync(), isEmpty);
    expect(capture.isRecording, isFalse);
  });

  test('cancel after automatic stop discards its uncollected WAV', () async {
    final ended = Completer<void>();
    capture.onMaxDuration = ended.complete;
    await capture.start(maxDuration: const Duration(milliseconds: 100));
    recorder.add(Uint8List(3200));
    await ended.future;
    await capture.cancel().timeout(const Duration(seconds: 5));
    expect(recordings.listSync(), isEmpty);
    expect(await capture.stop(), isNull);
  });

  test('starting again discards a preceding uncollected auto-stop result', () async {
    final ended = Completer<void>();
    capture.onMaxDuration = ended.complete;
    await capture.start(maxDuration: const Duration(milliseconds: 100));
    recorder.add(Uint8List(3200));
    await ended.future;
    // Wait for the recorder stream to flush; a retry while still recording
    // correctly returns false rather than opening two microphones.
    await recorder.closed.future;
    await Future<void>.delayed(Duration.zero);
    expect(await capture.start(maxDuration: const Duration(seconds: 10)), isTrue);
    await capture.cancel();
    expect(recordings.listSync(), isEmpty);
  });

  test('dispose while microphone opens waits for cleanup and rejects later calls', () async {
    final opened = Completer<void>();
    recorder.openGate = opened.future;
    final start = capture.start(maxDuration: const Duration(seconds: 10));
    await recorder.openRequested.future;
    final dispose = capture.dispose();
    opened.complete();
    expect(await start, isFalse);
    await dispose.timeout(const Duration(seconds: 5));
    expect(recordings.listSync(), isEmpty);
    expect(await capture.start(maxDuration: const Duration(seconds: 10)), isFalse);
    expect(await capture.transcribeFile('/unused.wav'), isNull);
  });
}

// Test the real recorder lifecycle and byte limiting without loading a native
// recogniser in flutter_test. This worker only counts bytes; model accuracy is
// covered separately by the package's on-device SELFTEST fixture path.
void _worker(List<Object?> args) {
  final reply = args.first as SendPort;
  final inbox = ReceivePort();
  String? path;
  var bytes = 0;
  reply.send(['ready', inbox.sendPort]);
  inbox.listen((dynamic raw) {
    final m = raw as List<Object?>;
    switch (m[0]) {
      case 'begin':
        path = m[1] as String;
        bytes = 0;
        File(path!).writeAsBytesSync([]);
      case 'pcm':
        bytes += (m[1] as TransferableTypedData).materialize().lengthInBytes;
      case 'end':
        final current = path;
        path = null;
        if (current == null || !(m[2] as bool)) {
          if (current != null) File(current).deleteSync();
          reply.send(['result', m[1], null]);
        } else {
          File(current).writeAsBytesSync(Uint8List(bytes));
          reply.send(['result', m[1], CaptureResult(
            current,
            bytes * 1000 ~/ 32000,
            Transcript.empty,
            const DeliveryMetrics(
              durationS: 0, words: 0, wpm: 0, pausesOver1s: 0,
              longestPauseS: 0, fillerCount: 0, fillers: {},
              loudnessDbMean: -100, loudnessDbSd: 0, trailingOff: false,
              pitchHzMean: null, pitchSemitoneSd: null, monotone: null, speechRatio: 0,
            ),
            0,
          )]);
        }
      case 'close':
        inbox.close();
    }
  });
}

class _Recorder implements AudioRecorder {
  Future<bool> permission = Future.value(true);
  Future<void>? openGate;
  final permissionRequested = Completer<void>();
  final openRequested = Completer<void>();
  Completer<void> closed = Completer<void>();
  StreamController<Uint8List>? _stream;
  int starts = 0;
  int stops = 0;
  bool failOpen = false;

  void add(Uint8List bytes) => _stream!.add(bytes);
  @override
  Future<bool> hasPermission({bool request = true}) {
    if (!permissionRequested.isCompleted) permissionRequested.complete();
    return permission;
  }
  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    starts++;
    if (!openRequested.isCompleted) openRequested.complete();
    await openGate;
    if (failOpen) throw StateError('microphone unavailable');
    closed = Completer<void>();
    return (_stream = StreamController<Uint8List>(sync: true)).stream;
  }
  @override
  Future<String?> stop() async {
    stops++;
    await _stream?.close();
    if (!closed.isCompleted) closed.complete();
    return null;
  }
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
