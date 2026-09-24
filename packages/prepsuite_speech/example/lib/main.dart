// On-device test app for prepsuite_speech.
//
// Build with --dart-define=SELFTEST=true to run the self test at launch and
// print results to the log (logcat tag "flutter", lines start with "PSX").
// The self test transcribes every *.wav in the app's external files dir
// under selftest/ (Android: /sdcard/Android/data/<id>/files/selftest/,
// iOS: Documents/selftest/), speaks with Norman, and records 3 s from the mic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prepsuite_speech/delivery_analyzer.dart' show readWav;
import 'package:prepsuite_speech/prepsuite_speech.dart';
import 'package:record/record.dart';

const selfTest = bool.fromEnvironment('SELFTEST');

void log(String s) {
  // ignore: avoid_print
  print('PSX $s');
}

void main() => runApp(const MaterialApp(home: SpeechDemo()));

/// Stands in for the microphone (the emulator mic is silent): streams a WAV's
/// samples as PCM16 in 50 ms chunks at real-time pace.
class WavReplayRecorder extends AudioRecorder {
  WavReplayRecorder(this.path);
  final String path;
  StreamController<Uint8List>? _ctrl;
  Timer? _timer;

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    final audio = readWav(path);
    final pcm = ByteData(audio.samples.length * 2);
    for (var i = 0; i < audio.samples.length; i++) {
      pcm.setInt16(i * 2, (audio.samples[i] * 32767).round().clamp(-32768, 32767), Endian.little);
    }
    final bytes = pcm.buffer.asUint8List();
    final ctrl = _ctrl = StreamController<Uint8List>();
    var off = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (off >= bytes.length) {
        _timer?.cancel();
        ctrl.close();
        return;
      }
      final end = math.min(off + 1600, bytes.length);
      ctrl.add(Uint8List.sublistView(bytes, off, end));
      off = end;
    });
    return ctrl.stream;
  }

  @override
  Future<String?> stop() async {
    _timer?.cancel();
    if (!(_ctrl?.isClosed ?? true)) await _ctrl!.close();
    return null;
  }

  @override
  Future<void> dispose() => stop();
}

class SpeechDemo extends StatefulWidget {
  const SpeechDemo({super.key});
  @override
  State<SpeechDemo> createState() => _SpeechDemoState();
}

class _SpeechDemoState extends State<SpeechDemo> {
  final capture = OfflineSpeechCapture();
  final voice = NormanVoice();
  double progress = 0;
  bool ready = false;
  double micLevel = 0, voiceLevel = 0;
  String partial = '';
  String output = '';
  bool recording = false;

  @override
  void initState() {
    super.initState();
    capture.level.listen((v) => setState(() => micLevel = v));
    capture.partialText.listen((t) => setState(() => partial = t));
    voice.level.listen((v) => setState(() => voiceLevel = v));
    capture.onMaxDuration = () => _stop();
    _prepare();
  }

  Future<void> _prepare() async {
    final sw = Stopwatch()..start();
    var lastLogged = -1;
    try {
      await SpeechModels.ensureReady(onProgress: (p) {
        setState(() => progress = p);
        final pct = (p * 10).floor();
        if (pct != lastLogged) {
          lastLogged = pct;
          log('models ${(p * 100).round()}%');
        }
      });
      log('models ready in ${sw.elapsedMilliseconds} ms at ${SpeechModels.paths!.root}');
      setState(() => ready = true);
      if (selfTest) {
        unawaited(_runSelfTest().catchError((Object e, StackTrace st) => log('selftest failed: $e\n$st')));
      }
    } catch (e) {
      log('models failed: $e');
      setState(() => output = '$e');
    }
  }

  Future<Directory> _testDir() async {
    final base = Platform.isAndroid
        ? (await getExternalStorageDirectory())!
        : await getApplicationDocumentsDirectory();
    return Directory('${base.path}/selftest');
  }

  void _show(String label, CaptureResult? r) {
    if (r == null) {
      log('$label: no result');
      return;
    }
    log('$label transcript: "${r.transcript.text}"');
    log('$label words: ${r.transcript.words.map((w) => '${w.text}@${w.startMs}-${w.endMs}').join(' ')}');
    log('$label duration_ms=${r.durationMs} peak=${r.peakLevel.toStringAsFixed(3)}');
    log('$label metrics: ${jsonEncode(r.metrics.toJson())}');
    setState(() => output = '${r.transcript.text}\n\n'
        '${const JsonEncoder.withIndent('  ').convert(r.metrics.toJson())}');
  }

  Future<void> _runSelfTest() async {
    log('selftest start');
    final t0 = Stopwatch()..start();
    await capture.warmUp();
    log('recogniser loaded in ${t0.elapsedMilliseconds} ms');

    final dir = await _testDir();
    // Created by the app so that `adb push` into it keeps the app's access.
    dir.createSync(recursive: true);
    final wavs = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.wav')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (wavs.isEmpty) log('no WAVs in ${dir.path}');
    for (final f in wavs) {
      final sw = Stopwatch()..start();
      final r = await capture.transcribeFile(f.path);
      log('${f.uri.pathSegments.last}: transcribed in ${sw.elapsedMilliseconds} ms');
      _show(f.uri.pathSegments.last, r);
    }

    // Live path with real speech: replay a WAV through the capture pipeline.
    final replay = wavs.where((f) => f.path.endsWith('b_answer.wav')).toList();
    if (replay.isNotEmpty) {
      final live = OfflineSpeechCapture(
        recorder: WavReplayRecorder(replay.first.path),
        models: SpeechModels.paths,
      );
      final partials = <String>[];
      final clock = Stopwatch()..start();
      final psub = live.partialText.listen((t) {
        partials.add(t);
        if (partials.length % 4 == 1) log('live partial @${clock.elapsedMilliseconds} ms: "$t"');
      });
      var levels = 0;
      var maxLevel = 0.0;
      final lsub = live.level.listen((v) {
        levels++;
        maxLevel = math.max(maxLevel, v);
      });
      final ended = Completer<void>();
      live.onMaxDuration = () {
        if (!ended.isCompleted) ended.complete();
      };
      log('live start: ${await live.start(maxDuration: const Duration(seconds: 60))}');
      await ended.future.timeout(const Duration(seconds: 40), onTimeout: () {});
      final sw = Stopwatch()..start();
      final r = await live.stop();
      log('live: ${partials.length} partial updates, $levels level events (max ${maxLevel.toStringAsFixed(2)}), '
          'final result ${sw.elapsedMilliseconds} ms after end of audio');
      _show('live', r);
      if (r != null) log('live wav bytes=${File(r.wavPath).lengthSync()}');
      await psub.cancel();
      await lsub.cancel();
      await live.dispose();
    }

    // Norman: level stream + completion.
    var maxLevel = 0.0, levelEvents = 0;
    final sub = voice.level.listen((v) {
      levelEvents++;
      if (v > maxLevel) maxLevel = v;
    });
    final sw = Stopwatch()..start();
    await voice.warmUp();
    log('voice loaded in ${sw.elapsedMilliseconds} ms');
    sw.reset();
    await voice.speak("Hi, I'm your interviewer today. What job are you preparing for?");
    log('speak #1 completed after ${sw.elapsedMilliseconds} ms; level events=$levelEvents max=${maxLevel.toStringAsFixed(2)}');

    // stop() must cut speech immediately.
    sw.reset();
    final long = voice.speak('Tell me about a time you helped solve a problem. '
        'Take your time, and walk me through what happened, what you did, and what changed.');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final stopAt = sw.elapsedMilliseconds;
    await voice.stop();
    await long;
    log('speak #2 stopped at $stopAt ms, returned at ${sw.elapsedMilliseconds} ms');
    await sub.cancel();

    // Microphone path (emulator mic is silent): record 3 s, auto-stop.
    final auto = Completer<void>();
    capture.onMaxDuration = () {
      if (!auto.isCompleted) auto.complete();
    };
    final started = await capture.start(maxDuration: const Duration(seconds: 3));
    log('mic start: $started');
    if (started) {
      await auto.future.timeout(const Duration(seconds: 10), onTimeout: () => log('mic auto-stop timeout'));
      final r = await capture.stop();
      _show('mic', r);
      if (r != null) log('mic wav exists=${File(r.wavPath).existsSync()} bytes=${File(r.wavPath).lengthSync()}');
    }
    capture.onMaxDuration = () => _stop();
    log('selftest done in ${t0.elapsedMilliseconds} ms');
  }

  Future<void> _record() async {
    await voice.stop();
    final ok = await capture.start(maxDuration: const Duration(seconds: 10));
    setState(() {
      recording = ok;
      partial = '';
      if (!ok) output = 'Could not start (permission denied?)';
    });
  }

  Future<void> _stop() async {
    final r = await capture.stop();
    setState(() => recording = false);
    _show('recording', r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('prepsuite_speech')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!ready) ...[
            Text('Preparing models ${(progress * 100).round()}%'),
            LinearProgressIndicator(value: progress),
          ],
          const Text('Mic level'),
          LinearProgressIndicator(value: micLevel),
          const SizedBox(height: 8),
          const Text('Norman level'),
          LinearProgressIndicator(value: voiceLevel),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: ready ? (recording ? _stop : _record) : null,
              child: Text(recording ? 'Stop' : 'Record (10 s)'),
            ),
            OutlinedButton(
              onPressed: ready
                  ? () => voice.speak("Hi, I'm your interviewer today. What job are you preparing for?")
                  : null,
              child: const Text('Speak'),
            ),
            OutlinedButton(onPressed: voice.stop, child: const Text('Stop voice')),
            OutlinedButton(onPressed: ready ? _runSelfTest : null, child: const Text('Self test')),
          ]),
          const SizedBox(height: 16),
          Text(partial, style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
          SelectableText(output, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }
}
