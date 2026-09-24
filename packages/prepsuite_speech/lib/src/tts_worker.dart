// Background isolate that owns the Piper (VITS) voice. It synthesises one
// sentence at a time, writes each as a WAV file and sends back its path plus
// a 20 ms loudness envelope for the level meter.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'asr_worker.dart' show levelFromRms;
import 'wav.dart';

const int envelopeMs = 20;

/// Entry point: args = [SendPort reply, Map<String, Object?> config].
void ttsWorkerMain(List<Object?> args) {
  final reply = args[0] as SendPort;
  final cfg = args[1] as Map<String, Object?>;
  final inbox = ReceivePort();
  late final so.OfflineTts tts;
  try {
    so.initBindings();
    tts = so.OfflineTts(
      so.OfflineTtsConfig(
        model: so.OfflineTtsModelConfig(
          vits: so.OfflineTtsVitsModelConfig(
            model: cfg['ttsModel'] as String,
            tokens: cfg['ttsTokens'] as String,
            dataDir: cfg['espeakData'] as String,
          ),
          numThreads: cfg['threads'] as int? ?? 2,
          debug: false,
        ),
        maxNumSenetences: 1,
      ),
    );
  } catch (e) {
    reply.send(['error', 'Could not load the Norman voice: $e']);
    inbox.close();
    return;
  }
  final sampleRate = tts.sampleRate;
  reply.send(['ready', inbox.sendPort]);

  inbox.listen((dynamic msg) {
    final m = msg as List<Object?>;
    switch (m[0]) {
      case 'speak':
        final id = m[1] as int;
        final text = m[2] as String;
        final dir = m[3] as String;
        final speed = m[4] as double;
        var k = 0;
        try {
          Directory(dir).createSync(recursive: true);
          tts.generateWithCallback(
            text: text,
            speed: speed,
            callback: (samples) {
              if (samples.isEmpty) return 1;
              final path = '$dir/norman_${id}_${k++}.wav';
              writeWavFile(path, samples, sampleRate);
              reply.send([
                'chunk',
                id,
                path,
                (samples.length * 1000 / sampleRate).round(),
                _envelope(samples, sampleRate),
              ]);
              return 1;
            },
          );
          reply.send(['done', id]);
        } catch (e) {
          reply.send(['failed', id, '$e']);
        }
      case 'close':
        tts.free();
        inbox.close();
    }
  });
}

Float32List _envelope(Float32List s, int sampleRate) {
  final win = math.max(1, sampleRate * envelopeMs ~/ 1000);
  final n = (s.length / win).ceil();
  final env = Float32List(n);
  for (var i = 0; i < n; i++) {
    final a = i * win, b = math.min(s.length, a + win);
    var sum = 0.0;
    for (var j = a; j < b; j++) {
      sum += s[j] * s[j];
    }
    env[i] = levelFromRms(math.sqrt(sum / (b - a)));
  }
  return env;
}
