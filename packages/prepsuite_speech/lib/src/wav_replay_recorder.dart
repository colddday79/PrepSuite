import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import 'asr_worker.dart' show asrSampleRate;
import 'wav.dart';

/// A microphone stand-in for emulators and on-device tests (the emulator
/// microphone records silence).
///
/// Pass it to `OfflineSpeechCapture(recorder: ...)`. Each recording takes the
/// next WAV in [paths] and streams it as PCM16 16 kHz mono in 50 ms chunks at
/// real-time pace, so partial text, the level meter, the saved WAV, the
/// transcript and the delivery metrics all come from the same live pipeline
/// as a real microphone. After the file ends it streams silence until the
/// recording is stopped, like a microphone in a quiet room (or closes the
/// stream when [closeAtEnd] is true). Once every file has been used, it
/// records from the real microphone.
class WavReplayRecorder extends AudioRecorder {
  WavReplayRecorder(List<String> paths, {this.closeAtEnd = false, this.log})
      : _queue = List.of(paths);

  /// Close the stream when the file ends instead of continuing with silence.
  final bool closeAtEnd;

  /// Receives one line per replayed file (for logs).
  final void Function(String line)? log;

  final List<String> _queue;
  StreamController<Uint8List>? _ctrl;
  Timer? _timer;
  bool _usingMic = false;

  /// Files not yet replayed.
  List<String> get remaining => List.unmodifiable(_queue);

  @override
  Future<bool> hasPermission({bool request = true}) async =>
      _queue.isNotEmpty || await super.hasPermission(request: request);

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    await _stopReplay();
    if (_queue.isEmpty) {
      _usingMic = true;
      log?.call('no test WAVs left; recording from the microphone');
      return super.startStream(config);
    }
    _usingMic = false;
    final path = _queue.removeAt(0);
    final audio = readWav(path);
    final pcm = floatToPcm16(_resample(audio.samples, audio.sampleRate, asrSampleRate));
    log?.call('replaying $path (${(pcm.length / 2 / asrSampleRate).toStringAsFixed(1)} s) '
        'instead of the microphone');
    final ctrl = _ctrl = StreamController<Uint8List>();
    const chunkBytes = asrSampleRate ~/ 20 * 2; // 50 ms
    final silence = Uint8List(chunkBytes);
    var offset = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (ctrl.isClosed) return;
      if (offset < pcm.length) {
        final end = math.min(offset + chunkBytes, pcm.length);
        ctrl.add(Uint8List.sublistView(pcm, offset, end));
        offset = end;
      } else if (closeAtEnd) {
        _timer?.cancel();
        ctrl.close();
      } else {
        ctrl.add(silence);
      }
    });
    return ctrl.stream;
  }

  Future<void> _stopReplay() async {
    _timer?.cancel();
    _timer = null;
    final ctrl = _ctrl;
    _ctrl = null;
    if (ctrl != null && !ctrl.isClosed) await ctrl.close();
  }

  @override
  Future<String?> stop() async {
    if (_usingMic) return super.stop();
    await _stopReplay();
    return null;
  }

  @override
  Future<void> cancel() async {
    if (_usingMic) return super.cancel();
    await _stopReplay();
  }

  @override
  Future<void> dispose() async {
    await _stopReplay();
    await super.dispose();
  }
}

/// Linear-interpolation resampling; enough for replaying test speech.
Float32List _resample(Float32List input, int from, int to) {
  if (from == to || input.isEmpty) return input;
  final n = (input.length * to / from).floor();
  final out = Float32List(n);
  final step = from / to;
  for (var i = 0; i < n; i++) {
    final x = i * step;
    final j = x.floor();
    final f = x - j;
    final a = input[j];
    final b = j + 1 < input.length ? input[j + 1] : a;
    out[i] = a + (b - a) * f;
  }
  return out;
}
