import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../coach/speech_adapter.dart';
import '../../design/assistant_avatar.dart';
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
  const IntakeScreen({super.key, this.preferTyping = false, this.questionCount = 3});

  final bool preferTyping;

  /// How many questions to ask: 3 for a short session, 1 for a quick drill.
  final int questionCount;

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
      final set = await _services.coach.questions(
        job: job,
        count: widget.questionCount,
        about: _services.profile.value.about,
      );
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

  AssistantMood get _mood => switch (_phase) {
        _Phase.asking => AssistantMood.speaking,
        _Phase.recording => AssistantMood.listening,
        _Phase.settingUp || _Phase.transcribing || _Phase.loading => AssistantMood.thinking,
        _ => AssistantMood.idle,
      };

  /// What the coach is doing, in words beside it.
  String get _status => switch (_phase) {
        _Phase.settingUp => 'Getting my voice ready',
        _Phase.asking => 'Asking',
        _Phase.ready => 'Your turn',
        _Phase.preparing => 'Getting ready to listen',
        _Phase.recording => 'Listening',
        _Phase.transcribing => 'Writing down what you said',
        _Phase.review => _typing ? 'Your turn' : 'Check what I heard',
        _Phase.unheard => "Didn't catch that",
        _Phase.micOff => 'Waiting for the microphone',
        _Phase.loading => 'Writing your questions',
        _Phase.error => "Couldn't get your questions",
      };

  String get _caption {
    final count = widget.questionCount;
    return count == 1 ? 'New practice · 1 question' : 'New practice · $count questions';
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phaseContent();
    return CoachScaffold(
      onClose: () => Navigator.of(context).maybePop(),
      progress: 0,
      progressLabel: 'Setting up your practice',
      caption: _caption,
      actions: _actions(),
      children: [
        CoachLine(mood: _mood, status: _status, level: _level),
        const SizedBox(height: Space.xl),
        RevealText(controller: _question, style: PrepType.question),
        const SizedBox(height: Space.s),
        Text(
          '${_typing ? 'Type' : 'Say'} the role and where it is. You can add one thing the job asks for.',
          style: PrepType.body,
        ),
        if (phase.isNotEmpty) ...[const SizedBox(height: Space.xxl), ...phase],
      ],
    );
  }

  List<Widget> _phaseContent() {
    switch (_phase) {
      case _Phase.asking:
      case _Phase.ready:
      case _Phase.preparing:
      case _Phase.recording:
      case _Phase.transcribing:
        final live = _phase == _Phase.recording || _phase == _Phase.transcribing;
        return [
          TranscriptCard(
            text: live ? _partial : '',
            placeholder: live ? 'Listening' : 'Your words will show up here as you talk.',
          ),
        ];
      case _Phase.settingUp:
        return [_SetupProgress(setup: _services.speechSetup.state.value)];
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
          PrepTextField(
            fieldKey: const ValueKey('job-field'),
            controller: _job,
            label: _typing ? 'The job' : 'What I heard',
            hint: 'Junior data analyst at a hospital',
            minLines: 2,
            autofocus: _typing && _job.text.isEmpty,
            onChanged: (_) => setState(() {}),
          ),
          if (!_typing) ...[
            const SizedBox(height: Space.s),
            Text('Fix any words I got wrong.', style: PrepType.meta),
          ],
        ];
      case _Phase.unheard:
        return const [ProblemNote(title: "We couldn't hear that.", body: 'Speak up, or type it.')];
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
        ];
      case _Phase.loading:
        return [
          AnswerQuote(_job.text.trim(), semanticPrefix: 'Your job'),
          const SizedBox(height: Space.xxl),
          const LoadingLine('Writing questions for this role'),
        ];
      case _Phase.error:
        return [
          ProblemNote(title: "Couldn't get your questions.", body: _error?.userMessage ?? 'Something went wrong. Try again.'),
        ];
    }
  }

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.asking:
      case _Phase.ready:
      case _Phase.preparing:
      case _Phase.recording:
      case _Phase.transcribing:
      case _Phase.unheard:
        return [_dock()];
      case _Phase.settingUp:
        return [
          QuietRow([QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: _typeInstead)]),
        ];
      case _Phase.review:
        final voiceMissing = _services.speechSetup.state.value.missing;
        return [
          PrimaryButton('Use this', onPressed: _job.text.trim().isEmpty ? null : _submit),
          if (!(_typing && voiceMissing))
            QuietRow([
              QuietButton(
                _typing ? 'Say it instead' : 'Record again',
                icon: _typing ? PrepIcons.mic : PrepIcons.replay,
                onPressed: _record,
              ),
            ]),
        ];
      case _Phase.micOff:
        return [
          PrimaryButton('Type instead', icon: PrepIcons.keyboard, onPressed: _typeInstead),
          QuietRow([
            QuietButton(
              _micBlocked ? 'Open settings' : 'Try again',
              onPressed: _micBlocked ? _services.mic.openSettings : _record,
            ),
          ]),
        ];
      case _Phase.loading:
        return [PrimaryButton('Use this', busy: true, onPressed: () {})];
      case _Phase.error:
        return [
          PrimaryButton('Try again', onPressed: _submit),
          QuietRow([QuietButton('Change the job', onPressed: () => setState(() => _phase = _Phase.review))]),
        ];
    }
  }

  /// The record button with "Type instead" and "Hear it again" beside it.
  Widget _dock() {
    final recording = _phase == _Phase.recording;
    final busy = _phase == _Phase.preparing || _phase == _Phase.transcribing;
    final Widget status;
    Widget? detail;
    if (recording) {
      status = ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (context, p, _) {
          final left = ((1 - p.clamp(0.0, 1.0)) * _maxJobRecording.inSeconds).ceil();
          return Text(
            'Recording, ${left}s left',
            style: PrepType.titleM.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          );
        },
      );
      detail = const Text('Tap to stop');
    } else if (_phase == _Phase.preparing) {
      status = const Text('Getting the microphone ready');
    } else if (_phase == _Phase.transcribing) {
      status = const Text('Turning your voice into text');
    } else {
      status = Text(_phase == _Phase.unheard ? 'Tap to try again' : 'Tap to answer');
      detail = const Text('Up to 10 seconds');
    }
    return RecordDock(
      button: RecordButton(
        recording: recording,
        countdown: true,
        progress: _progress,
        onPressed: busy ? null : (recording ? _stop : _record),
        semanticLabel: recording ? 'Stop recording' : 'Start recording the job',
      ),
      status: Semantics(liveRegion: !recording, child: status),
      detail: detail,
      sidesVisible: !recording && !busy,
      leading: DockAction(icon: PrepIcons.keyboard, label: 'Type instead', onPressed: _typeInstead),
      trailing: DockAction(
        icon: PrepIcons.speaker,
        label: 'Hear it again',
        semanticLabel: 'Hear the question again',
        onPressed: _phase == _Phase.ready || _phase == _Phase.unheard ? _ask : null,
      ),
    );
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
