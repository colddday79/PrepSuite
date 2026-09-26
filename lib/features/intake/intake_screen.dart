import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

enum _Phase { settingUp, asking, ready, preparing, recording, transcribing, review, unheard, micOff, loading, error }

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

  /// Why voice is unavailable (for example, a build without the speech files); typing is offered.
  String? _voiceNote;

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
      _services.speechSetup.state.addListener(_onSpeechSetup);
      unawaited(_services.speechSetup.prepare().catchError((Object _) {}));
      _begin();
    });
  }

  /// Waits for the offline speech set-up (first launch copies the model files) before the
  /// interviewer asks, and falls back to typing when voice is not available.
  void _begin() {
    final setup = _services.speechSetup.state.value;
    if (!_typing && setup.isFailed) {
      _voiceNote = setup.error;
      _typing = true;
    }
    if (!_typing && !setup.isReady) {
      _question.start(_jobQuestion);
      _question.showAll();
      setState(() => _phase = _Phase.settingUp);
      return;
    }
    _ask();
  }

  void _onSpeechSetup() {
    if (!mounted || _phase != _Phase.settingUp) return;
    final setup = _services.speechSetup.state.value;
    if (setup.isReady) {
      _ask();
    } else if (setup.isFailed) {
      _voiceNote = setup.error;
      _typeInstead();
    } else {
      setState(() {});
    }
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
    _services.speechSetup.state.removeListener(_onSpeechSetup);
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
      _prefillFromProfile();
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

  /// Someone who told the app their target job starts with it filled in; they can change it.
  void _prefillFromProfile() {
    final role = _services.profile.value.targetRole.trim();
    if (_job.text.trim().isEmpty && role.isNotEmpty) _job.text = role;
  }

  void _typeInstead() {
    _operation++;
    _services.voice.stop();
    _question.showAll();
    _prefillFromProfile();
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
      // Typing the job alone doesn't switch answers to typing; "Practise by typing" does, and so
      // does a phone where voice is not available.
      final session = PracticeSession(
        job: job,
        set: set,
        preferTyping: widget.preferTyping || _services.speechSetup.state.value.isFailed,
      );
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

  /// Large while the interviewer asks and listens, smaller once there is text to read or edit.
  double _presenceSize(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final talking = switch (_phase) {
      _Phase.settingUp || _Phase.asking || _Phase.ready || _Phase.preparing || _Phase.recording || _Phase.transcribing => true,
      _ => false,
    };
    if (!talking) return 152;
    return math.min(screen.width * 0.92, screen.height * 0.38).clamp(200.0, 420.0);
  }

  @override
  Widget build(BuildContext context) {
    return CoachScaffold(
      status: 'Your job',
      presenceSize: _presenceSize(context),
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
          const SizedBox(height: Space.xl),
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
                      return Text('${left}s left', style: PrepType.meta);
                    },
                  )
                : Text('10 seconds', style: PrepType.meta),
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
      case _Phase.settingUp:
        return [
          const SizedBox(height: Space.l),
          _SetupProgress(setup: _services.speechSetup.state.value),
          const SizedBox(height: Space.xl),
          Center(child: QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: _typeInstead)),
        ];
      case _Phase.transcribing:
        return const [SizedBox(height: Space.l), LoadingLine('Turning your voice into text')];
      case _Phase.preparing:
        return const [SizedBox(height: Space.l), LoadingLine('Preparing microphone')];
      case _Phase.review:
        final voiceNote = _voiceNote;
        final voiceMissing = _services.speechSetup.state.value.missing;
        return [
          if (voiceNote != null && _typing) ...[
            ProblemNote(
              title: "Voice isn't available.",
              body: kDebugMode && voiceMissing
                  ? '$voiceNote (Developers: run tools/voice/fetch_models.sh, then rebuild.)'
                  : voiceNote,
            ),
            const SizedBox(height: Space.xl),
          ],
          const SizedBox(height: Space.s),
          PrepTextField(
            fieldKey: const ValueKey('job-field'),
            controller: _job,
            hint: 'Junior data analyst at a hospital',
            minLines: 2,
            autofocus: _typing && _job.text.isEmpty,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.xxl),
          PrimaryButton('Use this', onPressed: _job.text.trim().isEmpty ? null : _submit),
          const SizedBox(height: Space.s),
          if (!(_typing && voiceMissing))
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
            body: 'Speak up, or type it.',
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
                ? _speechError ?? 'Try again, or type it.'
                : _micBlocked
                    ? 'Allow it in Settings, or type it.'
                    : 'Allow it when you try again, or type it.',
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

/// First-launch set-up of the offline speech files, said plainly with real progress.
class _SetupProgress extends StatelessWidget {
  const _SetupProgress({required this.setup});

  final SpeechReadiness setup;

  @override
  Widget build(BuildContext context) {
    final percent = (setup.progress * 100).floor();
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(setup.copying ? 'Setting up the voice on this phone' : 'Getting the voice ready', style: PrepType.bodyLMedium),
          const SizedBox(height: Space.xs),
          Text(
            setup.copying
                ? 'First launch only: copying the offline speech files. $percent%'
                : 'Loading offline speech. This takes a moment.',
            style: PrepType.meta,
          ),
          const SizedBox(height: Space.m),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(2)),
            child: LinearProgressIndicator(
              value: setup.copying ? setup.progress : null,
              minHeight: 2,
              color: PrepColors.accent,
              backgroundColor: PrepColors.line,
            ),
          ),
        ],
      ),
    );
  }
}
