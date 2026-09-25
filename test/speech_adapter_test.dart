import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite_speech/prepsuite_speech.dart' as native;

import 'package:prepsuite/coach/speech_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancelling model preparation cannot start a hidden recording', () async {
    final prepared = Completer<void>();
    final capture = _Capture();
    final adapter = SpeechCaptureAdapter(
      capture: capture,
      setup: SpeechSetup(prepareModels: (_) => prepared.future),
    );
    final start = adapter.start(maxDuration: const Duration(seconds: 10));
    final stop = adapter.stop();
    final cancel = adapter.cancel();
    prepared.complete();

    expect(await start, isFalse);
    expect(await stop, isNull);
    await cancel;
    expect(capture.starts, 0);
    expect(capture.stops, 0);
    await adapter.dispose();
  });

  test('a cancelled start finishes cleanup before the next capture', () async {
    final opened = Completer<bool>();
    final startCalled = Completer<void>();
    final capture = _Capture()
      ..onStart = () {
        startCalled.complete();
        return opened.future;
      };
    final adapter = SpeechCaptureAdapter(capture: capture, setup: SpeechSetup(prepareModels: (_) async {}));
    final first = adapter.start(maxDuration: const Duration(seconds: 10));
    await startCalled.future;
    final cancel = adapter.cancel();
    opened.complete(true);
    expect(await first, isFalse);
    capture.onStart = null;
    final second = adapter.start(maxDuration: const Duration(seconds: 10));
    await cancel;
    expect(await second, isTrue);
    expect(capture.recording, isTrue);
    await adapter.dispose();
    expect(capture.recording, isFalse);
  });

  test('stop maps measured delivery and deletes the private recording', () async {
    final dir = await Directory.systemTemp.createTemp('prepsuite_adapter_');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/answer.wav').writeAsBytes([1, 2]);
    final capture = _Capture()..result = _result(file.path);
    final adapter = SpeechCaptureAdapter(capture: capture, setup: SpeechSetup(prepareModels: (_) async {}));

    expect(await adapter.start(maxDuration: const Duration(seconds: 10)), isTrue);
    final result = await adapter.stop();
    expect(result?.transcript.text, 'I manage a shop.');
    expect(result?.metrics.wpm, 96);
    expect(result?.metrics.pitchSemitoneSd, 2.2);
    expect(result?.wavPath, isEmpty);
    expect(await file.exists(), isFalse);
    await adapter.dispose();
  });

  test('cancelled transcription is discarded and its audio is deleted', () async {
    final dir = await Directory.systemTemp.createTemp('prepsuite_adapter_');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/answer.wav').writeAsBytes([1, 2]);
    final transcribed = Completer<native.CaptureResult?>();
    final capture = _Capture()..onStop = () => transcribed.future;
    final adapter = SpeechCaptureAdapter(capture: capture, setup: SpeechSetup(prepareModels: (_) async {}));
    await adapter.start(maxDuration: const Duration(seconds: 10));
    final result = adapter.stop();
    await adapter.cancel();
    transcribed.complete(_result(file.path));

    expect(await result, isNull);
    expect(await file.exists(), isFalse);
    await adapter.dispose();
  });

  test('native transcription failures become readable retry errors', () async {
    final capture = _Capture()..onStop = () => Future.error(StateError('decoder failed'));
    final adapter = SpeechCaptureAdapter(capture: capture, setup: SpeechSetup(prepareModels: (_) async {}));
    await adapter.start(maxDuration: const Duration(seconds: 10));
    expect(await adapter.stop(), isNull);
    expect(speechErrorMessage(adapter), contains('Try again or type'));
    await adapter.dispose();
  });

  test('transcribing a supplied WAV preserves the source file', () async {
    final dir = await Directory.systemTemp.createTemp('prepsuite_adapter_');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/fixture.wav').writeAsBytes([1, 2]);
    final capture = _Capture()..result = _result(file.path);
    final adapter = SpeechCaptureAdapter(capture: capture, setup: SpeechSetup(prepareModels: (_) async {}));
    expect((await adapter.transcribeFile(file.path))?.wavPath, file.path);
    expect(await file.exists(), isTrue);
    await adapter.dispose();
  });
}

native.CaptureResult _result(String path) => native.CaptureResult(
  path,
  2500,
  const native.Transcript('I manage a shop.', [native.TimedWord('I', 0, 150)], true),
  const native.DeliveryMetrics(
    durationS: 2.5,
    words: 4,
    wpm: 96,
    pausesOver1s: 0,
    longestPauseS: 0,
    fillerCount: 0,
    fillers: {},
    loudnessDbMean: -24,
    loudnessDbSd: 3,
    trailingOff: false,
    pitchHzMean: 180,
    pitchSemitoneSd: 2.2,
    monotone: false,
    speechRatio: 0.9,
  ),
  0.4,
);

class _Capture implements native.SpeechCapture {
  int starts = 0;
  int stops = 0;
  bool recording = false;
  native.CaptureResult? result;
  Future<bool> Function()? onStart;
  Future<native.CaptureResult?> Function()? onStop;

  @override
  Stream<double> get level => const Stream.empty();
  @override
  Stream<String> get partialText => const Stream.empty();
  @override
  Future<bool> start({required Duration maxDuration}) async {
    starts++;
    recording = await (onStart?.call() ?? Future.value(true));
    return recording;
  }
  @override
  Future<native.CaptureResult?> stop() async {
    stops++;
    recording = false;
    return await (onStop?.call() ?? Future.value(result));
  }
  @override
  Future<void> cancel() async { recording = false; }
  @override
  Future<native.CaptureResult?> transcribeFile(String wavPath) async => result;
}
