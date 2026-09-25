import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../coach/speech_adapter.dart';
import '../../design/components.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';
import '../interview/interview_screen.dart';

const _jobQuestion = 'What job are you preparing for?';
const _maxJobRecording = Duration(seconds: 10);

enum _Phase { asking, ready, preparing, recording, transcribing, review, unheard, micOff, loading, error }

/// Step one: the interviewer asks for the job, the person says it (10 seconds at most), checks
/// what we heard, and the coach writes questions for that role.
class IntakeScreen extends StatefulWidget {
  const IntakeScreen({super.key, this.preferTyping = false});

  final bool preferTyping;

  @override
  State<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends State<IntakeScreen> with WidgetsBindingObserver {
  late AppServices _services;
  final _question = RevealController();
  final _level = LevelMix();
  final _progress = ValueNotifier<double>(0);
  final _job = TextEditingController();
  StreamSubscription<String>? _partialSub;
  Timer? _ticker;
  _Phase _phase = _Phase.asking;
  String _partial = '';
  bool _typing = false;
  bool _micBlocked = false;
  bool _micFailed = false;
  CoachException? _error;
  int _operation = 0;
  bool _handedOff = false;
  String? _speechError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _typing = widget.preferTyping;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _level.listenTo(_services.voice.level);
      _level.listenTo(_services.speech.level);
      _partialSub = _services.speech.partialText.listen((text) {
        if (mounted && _phase == _Phase.recording) setState(() => _partial = text);
      });
      _ask();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _operation++;
    _ticker?.cancel();
    _partialSub?.cancel();
    if (!_handedOff) {
      _services.voice.stop();
      _services.speech.cancel();
    }
    _question.dispose();
    _level.dispose();
    _progress.dispose();
    _job.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final operation = ++_operation;
    _question.start(_jobQuestion);
    if (_typing) {
      _question.showAll();
      setState(() => _phase = _Phase.review);
      return;
    }
    setState(() => _phase = _Phase.asking);
    try {
      await _services.voice.speak(_jobQuestion);
    } catch (_) {
      // A silent interviewer is not a reason to stop: the question is on screen.
    }
    if (!mounted || operation != _operation) return;
    _question.showAll();
    _level.rest();
    if (_phase == _Phase.asking) setState(() => _phase = _Phase.ready);
  }

  Future<void> _record() async {
    if (_phase == _Phase.recording) return _stop();
    if (_phase == _Phase.preparing || _phase == _Phase.transcribing || _phase == _Phase.loading) return;
    final operation = ++_operation;
    setState(() {
      _phase = _Phase.preparing;
      _speechError = null;
    });
    _question.showAll();
    try {
      await _services.voice.stop();
      if (!mounted || operation != _operation) return;
      final access = await _services.mic.request();
      if (!mounted || operation != _operation) return;
      if (access != MicAccess.granted) {
        setState(() {
          _micBlocked = access == MicAccess.blocked;
          _micFailed = false;
          _phase = _Phase.micOff;
        });
        return;
      }
      final started = await _services.speech.start(maxDuration: _maxJobRecording);
      if (!mounted || operation != _operation) {
        if (started) await _services.speech.cancel();
        return;
      }
      if (!started) throw StateError('Speech capture could not start');
    } catch (_) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _micBlocked = false;
        _micFailed = true;
        _speechError = speechErrorMessage(_services.speech);
        _phase = _Phase.micOff;
      });
      return;
    }
    var elapsed = 0;
    _progress.value = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed += 100;
      _progress.value = elapsed / _maxJobRecording.inMilliseconds;
      if (elapsed >= _maxJobRecording.inMilliseconds) _stop();
    });
    setState(() {
      _partial = '';
      _typing = false;
      _phase = _Phase.recording;
    });
  }

  Future<void> _stop() async {
    if (_phase != _Phase.recording) return;
    _ticker?.cancel();
    setState(() => _phase = _Phase.transcribing);
    CaptureResult? result;
    try {
      result = await _services.speech.stop();
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    _level.rest();
    final heard = result?.transcript.text.trim() ?? '';
    if (heard.isEmpty) {
      setState(() => _phase = _Phase.unheard);
      return;
    }
    _job.text = heard;
    setState(() => _phase = _Phase.review);
  }

  void _typeInstead() {
    _operation++;
    _services.voice.stop();
    _question.showAll();
    setState(() {
      _typing = true;
      _phase = _Phase.review;
    });
  }

  Future<void> _submit() async {
    if (_phase == _Phase.loading) return;
    final job = _job.text.trim();
    if (job.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _phase = _Phase.loading;
    });
    try {
      final set = await _services.coach.questions(job: job, count: 5);
      if (!mounted) return;
      // Typing the job alone doesn't switch answers to typing; only "Practise by typing" does.
      final session = PracticeSession(job: job, set: set, preferTyping: widget.preferTyping);
      await _services.voice.stop();
      if (!mounted) return;
      _handedOff = true;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => InterviewScreen(session: session)),
      );
    } on CoachException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _phase = _Phase.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = CoachException(CoachErrorKind.badResponse, message: '$e');
        _phase = _Phase.error;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused && state != AppLifecycleState.detached) return;
    _services.voice.stop();
    if (_phase == _Phase.recording) {
      unawaited(_stop());
    } else if (_phase == _Phase.preparing) {
      _operation++;
      _services.speech.cancel();
      setState(() => _phase = _Phase.ready);
    } else if (_phase == _Phase.asking) {
      _operation++;
      _question.showAll();
      setState(() => _phase = _Phase.ready);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoachScaffold(
      status: 'Your job',
      presenceSize: 216,
      level: _level,
      onClose: () => Navigator.of(context).maybePop(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RevealText(controller: _question, style: PrepType.question),
            const SizedBox(height: Space.s),
            ..._phaseContent(),
          ],
        ),
      ),
    );
  }

  List<Widget> _phaseContent() {
    switch (_phase) {
      // Ready and recording share one layout, so the record button never moves under a finger.
      case _Phase.asking:
      case _Phase.ready:
      case _Phase.recording:
        final recording = _phase == _Phase.recording;
        return [
          Text('Say it in a few words, like “barista at a busy café” or “junior web developer”.', style: PrepType.body),
          const SizedBox(height: Space.x3),
          Center(
            child: RecordButton(recording: recording, countdown: true, progress: _progress, onPressed: recording ? _stop : _record),
          ),
          const SizedBox(height: Space.m),
          Center(
            child: recording
                ? ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (context, p, _) {
                      final left = ((1 - p.clamp(0.0, 1.0)) * _maxJobRecording.inSeconds).ceil();
                      return Text('$left s left. Tap to stop.', style: PrepType.meta);
                    },
                  )
                : Text('Tap and talk. You have 10 seconds.', style: PrepType.meta),
          ),
          const SizedBox(height: Space.m),
          if (recording)
            Text(
              _partial.isEmpty ? 'Listening' : _partial,
              textAlign: TextAlign.center,
              style: PrepType.bodyL.copyWith(color: _partial.isEmpty ? PrepColors.text3 : PrepColors.text),
            )
          else
            Center(child: QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: _typeInstead)),
        ];
      case _Phase.transcribing:
        return const [SizedBox(height: Space.l), LoadingLine('Turning your voice into text')];
      case _Phase.preparing:
        return const [SizedBox(height: Space.l), LoadingLine('Preparing microphone')];
      case _Phase.review:
        return [
          Text(
            _typing ? 'Type the job you want, in a few words.' : "Here's what we heard. Fix anything we got wrong.",
            style: PrepType.body,
          ),
          const SizedBox(height: Space.m),
          PrepTextField(
            fieldKey: const ValueKey('job-field'),
            controller: _job,
            hint: 'For example: barista at a busy café',
            minLines: 2,
            autofocus: _typing && _job.text.isEmpty,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.xxl),
          PrimaryButton('Use this', onPressed: _job.text.trim().isEmpty ? null : _submit),
          const SizedBox(height: Space.s),
          Center(
            child: QuietButton(
              _typing ? 'Say it instead' : 'Record again',
              icon: _typing ? PrepIcons.mic : PrepIcons.replay,
              onPressed: _record,
            ),
          ),
        ];
      case _Phase.unheard:
        return [
          const ProblemNote(
            title: "We couldn't hear that.",
            body: 'Check that nothing is covering the microphone and speak a little louder. Or type the job instead.',
          ),
          const SizedBox(height: Space.xxl),
          Center(child: RecordButton(recording: false, countdown: true, progress: _progress, onPressed: _record)),
          const SizedBox(height: Space.s),
          Center(child: QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: _typeInstead)),
        ];
      case _Phase.micOff:
        return [
          ProblemNote(
            title: _micFailed ? "The microphone didn't start." : 'The microphone is off.',
            body: _micFailed
                ? _speechError ?? 'Another app may be using it. Try again, or type the job instead.'
                : _micBlocked
                    ? 'Allow the microphone for PrepSuite in Settings, or type the job instead.'
                    : 'PrepSuite needs the microphone to hear you. You can allow it when you try again, or type the job instead.',
          ),
          const SizedBox(height: Space.xxl),
          PrimaryButton('Type instead', onPressed: _typeInstead),
          const SizedBox(height: Space.s),
          Center(
            child: QuietButton(
              _micBlocked ? 'Open settings' : 'Try again',
              onPressed: _micBlocked ? _services.mic.openSettings : _record,
            ),
          ),
        ];
      case _Phase.loading:
        return [
          Text(_job.text.trim(), style: PrepType.bodyL.copyWith(color: PrepColors.text2)),
          const SizedBox(height: Space.xxl),
          const LoadingLine('Writing questions for this role'),
        ];
      case _Phase.error:
        return [
          ProblemNote(title: "Couldn't get your questions.", body: _error?.userMessage ?? 'Something went wrong. Try again.'),
          const SizedBox(height: Space.xxl),
          PrimaryButton('Try again', onPressed: _submit),
          const SizedBox(height: Space.s),
          Center(child: QuietButton('Change the job', onPressed: () => setState(() => _phase = _Phase.review))),
        ];
    }
  }
}
