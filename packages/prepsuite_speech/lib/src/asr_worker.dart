// Background isolate that owns the sherpa-onnx streaming recogniser, writes
// the WAV file and computes delivery metrics. Nothing here runs on the UI
// isolate.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'delivery_analyzer.dart';
import 'types.dart';
import 'wav.dart';
import 'words.dart';

const int asrSampleRate = 16000;

/// Silence fed before the audio (streaming models miss a word that starts at
/// t=0) and after it (the Kroko model decodes in 1.28 s chunks).
const double _leadS = 0.3;
const double _tailS = 2.5;

/// Maps an RMS value to a 0..1 meter level (-60 dBFS → 0, -10 dBFS → 1).
double levelFromRms(double rms) {
  if (rms <= 1e-6) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 60) / 50).clamp(0.0, 1.0);
}

/// Entry point: args = [SendPort reply, Map<String, Object?> config].
void asrWorkerMain(List<Object?> args) {
  final reply = args[0] as SendPort;
  final cfg = args[1] as Map<String, Object?>;
  final inbox = ReceivePort();
  late final so.OnlineRecognizer recognizer;
  try {
    so.initBindings();
    recognizer = so.OnlineRecognizer(
      so.OnlineRecognizerConfig(
        model: so.OnlineModelConfig(
          transducer: so.OnlineTransducerModelConfig(
            encoder: cfg['asrEncoder'] as String,
            decoder: cfg['asrDecoder'] as String,
            joiner: cfg['asrJoiner'] as String,
          ),
          tokens: cfg['asrTokens'] as String,
          numThreads: cfg['threads'] as int? ?? 2,
          debug: false,
        ),
        enableEndpoint: false,
      ),
    );
  } catch (e) {
    reply.send(['error', 'Could not load speech recogniser: $e']);
    inbox.close();
    return;
  }
  reply.send(['ready', inbox.sendPort]);

  final worker = _AsrWorker(recognizer, reply);
  inbox.listen((dynamic msg) {
    final m = msg as List<Object?>;
    switch (m[0]) {
      case 'begin':
        worker.begin(m[1] as String);
      case 'pcm':
        worker.pcm((m[1] as TransferableTypedData).materialize().asUint8List());
      case 'end':
        worker.end(m[1] as int, keep: m[2] as bool);
      case 'file':
        worker.file(m[1] as int, m[2] as String);
      case 'close':
        worker.close();
        recognizer.free();
        inbox.close();
    }
  });
}

class _Live {
  final so.OnlineStream stream;
  final StreamingWavWriter wav;
  final String path;
  final BytesBuilder pcm = BytesBuilder(copy: false);
  String partial = '';
  _Live(this.stream, this.wav, this.path);
}

class _AsrWorker {
  final so.OnlineRecognizer rec;
  final SendPort reply;
  final DeliveryAnalyzer analyzer = const DeliveryAnalyzer();
  _Live? live;

  _AsrWorker(this.rec, this.reply);

  void begin(String path) {
    _dropLive();
    try {
      File(path).parent.createSync(recursive: true);
      final stream = rec.createStream();
      stream.acceptWaveform(
        samples: Float32List((_leadS * asrSampleRate).round()),
        sampleRate: asrSampleRate,
      );
      live = _Live(stream, StreamingWavWriter(path, asrSampleRate), path);
    } catch (e) {
      reply.send(['log', 'begin failed: $e']);
    }
  }

  void pcm(Uint8List bytes) {
    final l = live;
    if (l == null || bytes.isEmpty) return;
    l.wav.add(bytes);
    l.pcm.add(bytes);
    l.stream.acceptWaveform(samples: pcm16ToFloat(bytes), sampleRate: asrSampleRate);
    while (rec.isReady(l.stream)) {
      rec.decode(l.stream);
    }
    final text = normalizeTranscriptText(rec.getResult(l.stream).text);
    if (text != l.partial) {
      l.partial = text;
      reply.send(['partial', text]);
    }
  }

  void end(int id, {required bool keep}) {
    final l = live;
    live = null;
    if (l == null) {
      reply.send(['result', id, null]);
      return;
    }
    try {
      l.wav.close();
      if (!keep) {
        l.stream.free();
        File(l.path).deleteSync();
        reply.send(['result', id, null]);
        return;
      }
      final samples = pcm16ToFloat(l.pcm.takeBytes());
      reply.send(['result', id, _finish(l.stream, samples, asrSampleRate, l.path)]);
    } catch (e) {
      reply.send(['failed', id, '$e']);
    }
  }

  void file(int id, String path) {
    try {
      final audio = readWav(path);
      final stream = rec.createStream();
      stream.acceptWaveform(
        samples: Float32List((_leadS * audio.sampleRate).round()),
        sampleRate: audio.sampleRate,
      );
      const chunk = 3200;
      for (var i = 0; i < audio.samples.length; i += chunk) {
        final end = math.min(i + chunk, audio.samples.length);
        stream.acceptWaveform(
          samples: Float32List.sublistView(audio.samples, i, end),
          sampleRate: audio.sampleRate,
        );
        while (rec.isReady(stream)) {
          rec.decode(stream);
        }
      }
      reply.send(['result', id, _finish(stream, audio.samples, audio.sampleRate, path)]);
    } catch (e) {
      reply.send(['failed', id, '$e']);
    }
  }

  CaptureResult _finish(so.OnlineStream stream, Float32List samples, int sampleRate, String path) {
    stream.acceptWaveform(
      samples: Float32List((_tailS * sampleRate).round()),
      sampleRate: sampleRate,
    );
    stream.inputFinished();
    while (rec.isReady(stream)) {
      rec.decode(stream);
    }
    final r = rec.getResult(stream);
    stream.free();

    final rawText = r.text.trim();
    final allCaps = rawText.isNotEmpty && !RegExp(r'[a-z]').hasMatch(rawText);
    final text = normalizeTranscriptText(rawText);
    final fa = analyzer.frames(samples, sampleRate);
    var words = tokensToWords(r.tokens, r.timestamps, offsetMs: (_leadS * 1000).round());
    words = analyzer.refineWordEnds(words, fa);
    final durationMs = (samples.length * 1000 / sampleRate).round();
    words = [
      for (final w in words)
        TimedWord(
          normalizeWord(w.text, allCaps: allCaps),
          math.min(w.startMs, durationMs),
          math.min(w.endMs, durationMs),
        ),
    ];
    final transcript = Transcript(text, words, true);
    final metrics = analyzer.metrics(fa, samples, sampleRate, transcript);
    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    return CaptureResult(path, durationMs, transcript, metrics, math.min(peak, 1.0));
  }

  void _dropLive() {
    final l = live;
    live = null;
    if (l == null) return;
    try {
      l.wav.close();
      l.stream.free();
    } catch (_) {}
  }

  void close() => _dropLive();
}
