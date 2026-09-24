import 'dart:async';
import 'dart:math' as math;

import 'contracts.dart';

/// Stands in for the on-device recognizer until packages/prepsuite_speech is wired in.
/// It animates a speech-like level, streams a canned transcript word by word, and on [stop]
/// returns that transcript with plausible delivery metrics, so the whole flow can be tapped
/// through on an emulator or in widget tests.
class FakeSpeechCapture implements SpeechCapture {
  FakeSpeechCapture({
    this.jobText = 'I want a job as a junior barista at a busy coffee shop in the city.',
    List<String>? answers,
    this.tick = const Duration(milliseconds: 50),
    this.msPerWord = 380,
  }) : answers = answers ?? _cannedAnswers;

  final String jobText;
  final List<String> answers;
  final Duration tick;
  final int msPerWord;

  /// When true, the next [stop] returns an empty transcript (to exercise "we couldn't hear you").
  bool silentNext = false;

  final _level = StreamController<double>.broadcast();
  final _partial = StreamController<String>.broadcast();
  Timer? _timer;
  bool _active = false;
  int _elapsedMs = 0;
  int _maxMs = 0;
  String _script = '';
  int _answerIndex = 0;

  @override
  Stream<double> get level => _level.stream;

  @override
  Stream<String> get partialText => _partial.stream;

  @override
  Future<bool> start({required Duration maxDuration}) async {
    if (_active) return true;
    // Short captures are the job question; longer ones are interview answers.
    _script = maxDuration <= const Duration(seconds: 15) ? jobText : answers[_answerIndex++ % answers.length];
    _active = true;
    _elapsedMs = 0;
    _maxMs = maxDuration.inMilliseconds;
    var shownWords = 0;
    final words = _words(_script);
    _timer = Timer.periodic(tick, (_) {
      _elapsedMs += tick.inMilliseconds;
      final t = _elapsedMs / 1000;
      final syllables = (math.sin(t * 11) * 0.5 + 0.5) * (math.sin(t * 2.3) * 0.35 + 0.65);
      _level.add(silentNext ? 0.02 : (0.18 + 0.62 * syllables).clamp(0.0, 1.0));
      final due = math.min(words.length, _elapsedMs ~/ msPerWord);
      if (!silentNext && due > shownWords) {
        shownWords = due;
        _partial.add(words.take(shownWords).join(' '));
      }
      if (_elapsedMs >= _maxMs) _timer?.cancel();
    });
    return true;
  }

  @override
  Future<CaptureResult?> stop() async {
    if (!_active) return null;
    _timer?.cancel();
    _active = false;
    _level.add(0);
    final silent = silentNext;
    silentNext = false;
    final text = silent ? '' : _script;
    return _result(text, math.max(_elapsedMs, 600));
  }

  @override
  Future<void> cancel() async {
    _timer?.cancel();
    _active = false;
    _level.add(0);
  }

  @override
  Future<CaptureResult?> transcribeFile(String wavPath) async => null;

  CaptureResult _result(String text, int elapsedMs) {
    final words = _words(text);
    // Pretend the speaker got through the whole script even if the button was tapped early.
    final durationS = words.isEmpty ? elapsedMs / 1000 : math.max(elapsedMs / 1000, words.length * 0.42);
    final fillers = <String, int>{};
    for (final w in words) {
      final key = w.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (key == 'um' || key == 'uh' || key == 'like') fillers[key] = (fillers[key] ?? 0) + 1;
    }
    final timed = <TimedWord>[];
    var at = 200;
    for (final w in words) {
      timed.add(TimedWord(w, at, at + 300));
      at += 420;
    }
    final metrics = DeliveryMetrics(
      durationS: double.parse(durationS.toStringAsFixed(1)),
      words: words.length,
      wpm: words.isEmpty ? 0 : (words.length / durationS * 60).round(),
      pausesOver1s: words.length > 30 ? 3 : (words.isEmpty ? 0 : 1),
      longestPauseS: words.isEmpty ? 0 : 1.8,
      fillerCount: fillers.values.fold(0, (a, b) => a + b),
      fillers: fillers,
      loudnessDbMean: words.isEmpty ? -58 : -24.5,
      loudnessDbSd: words.isEmpty ? 1.2 : 5.1,
      trailingOff: words.length > 30,
      pitchHzMean: words.isEmpty ? null : 182,
      pitchSemitoneSd: words.isEmpty ? null : 1.6,
      monotone: words.isEmpty ? null : true,
      speechRatio: words.isEmpty ? 0.02 : 0.74,
    );
    return CaptureResult('/fake/answer.wav', (durationS * 1000).round(), Transcript(text, timed, true), metrics, words.isEmpty ? 0.03 : 0.82);
  }

  static List<String> _words(String text) => text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  static const _cannedAnswers = [
    'Um, so I am a really hard worker and I like working with people. At my last job, like, we were always busy and I just, um, did my best to keep up with everything.',
    'One time a customer was upset because their order was wrong. I said sorry, remade it straight away and gave them a voucher. They came back the next week and asked for me.',
    'I think my weakness is that I, uh, take on too much. I am learning to ask for help earlier, like when the queue gets long I call someone over before it gets out of hand.',
  ];
}

/// Stands in for the Norman interviewer voice: "speaks" for about 60 ms per word and animates
/// a level while it does.
class FakeInterviewerVoice implements InterviewerVoice {
  FakeInterviewerVoice({this.perWord = const Duration(milliseconds: 60), this.tick = const Duration(milliseconds: 40)});

  final Duration perWord;
  final Duration tick;

  final _level = StreamController<double>.broadcast();
  Timer? _timer;
  Completer<void>? _speaking;

  @override
  Stream<double> get level => _level.stream;

  @override
  Future<void> speak(String text) async {
    await stop();
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final totalMs = perWord.inMilliseconds * words;
    final done = Completer<void>();
    _speaking = done;
    var elapsed = 0;
    _timer = Timer.periodic(tick, (timer) {
      elapsed += tick.inMilliseconds;
      _level.add(0.3 + 0.5 * (math.sin(elapsed / 70).abs()));
      if (elapsed >= totalMs) {
        timer.cancel();
        _level.add(0);
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final current = _speaking;
    _speaking = null;
    if (current != null && !current.isCompleted) {
      _level.add(0);
      current.complete();
    }
  }
}
