import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../coach/speech_adapter.dart';
import '../../design/assistant_avatar.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';
import '../interview/interview_screen.dart';

const _jobQuestion = 'What job are you preparing for?';
const _maxJobRecording = Duration(seconds: 10);

enum _Phase { settingUp, asking, ready, preparing, recording, transcribing, review, unheard, micOff, loading, error }

/// Step one: the coach, big on its lit floor, asks for the job; the person says it on the record
/// dial (10 seconds at most), checks what we heard, and the coach writes questions for that role.
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
        _Phase.review when !_typing => AssistantMood.happy,
        _ => AssistantMood.idle,
      };

  /// What the coach is doing, for screen readers (the robot's face shows it on screen).
  String get _status => switch (_phase) {
        _Phase.settingUp => 'Getting ready',
        _Phase.asking => 'Asking',
        _Phase.ready => 'Your turn',
        _Phase.preparing => 'Getting ready',
        _Phase.recording => 'Listening',
        _Phase.transcribing => 'Writing it down',
        _Phase.review => _typing ? 'Your turn' : 'Check your words',
        _Phase.unheard => "Didn't catch that",
        _Phase.micOff => 'Microphone off',
        _Phase.loading => 'Writing your questions',
        _Phase.error => "Couldn't get your questions",
      };

  /// The phases where the question is the page and the coach is the hero.
  bool get _asking => switch (_phase) {
        _Phase.review || _Phase.loading || _Phase.error => false,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final count = widget.questionCount;
    return CoachScaffold(
      onClose: () => Navigator.of(context).maybePop(),
      progress: 0,
      progressLabel: 'New practice, $count ${count == 1 ? 'question' : 'questions'}',
      segments: count,
      dock: _dock(),
      builder: _page,
    );
  }

  List<Widget> _page(BuildContext context, PageRoom room) {
    final hero = _asking;
    final checking = _phase == _Phase.review && !_typing;
    final style = hero ? PrepType.question : PrepType.questionM;
    final phase = _phaseContent();
    // Room for the question and for three lines of what is being heard, so the coach keeps its size.
    final words = Space.l +
        measureText(context, _jobQuestion, style, room.width) +
        Space.l +
        measureText(context, 'a\nb\nc', PrepType.bodyL, room.width);
    final size = hero ? heroCoachSize(context, room, words) : compactCoachSize(context);
    return [
      SizedBox(height: hero ? heroLeadIn(room, words, size) : 0),
      CoachStage(mood: _mood, status: _status, level: _level, size: size, dial: hero),
      const SizedBox(height: Space.l),
      if (checking)
        Semantics(
          header: true,
          child: Text('Check your words', style: PrepType.titleL, textAlign: TextAlign.center),
        )
      else
        RevealText(controller: _question, style: style, textAlign: TextAlign.center),
      if (phase.isNotEmpty) ...[SizedBox(height: hero ? Space.l : Space.xl), ...phase],
    ];
  }

  List<Widget> _phaseContent() {
    switch (_phase) {
      case _Phase.asking:
      case _Phase.ready:
      case _Phase.preparing:
      case _Phase.recording:
      case _Phase.transcribing:
        // Nothing until the first words arrive; the dock under the page says what is happening.
        final live = _phase == _Phase.recording || _phase == _Phase.transcribing;
        return [if (live && _partial.trim().isNotEmpty) LiveWords(_partial)];
      case _Phase.settingUp:
        return const [];
      case _Phase.review:
        final voiceNote = _voiceNote;
        final voiceMissing = _services.speechSetup.state.value.missing;
        return [
          if (voiceNote != null && _typing) ...[
            ProblemNote(
              centered: true,
              title: "Voice isn't available.",
              body: kDebugMode && voiceMissing
                  ? '$voiceNote (Developers: run tools/voice/fetch_models.sh, then rebuild.)'
                  : voiceNote,
            ),
            const SizedBox(height: Space.xl),
          ],
          MetalField(
            fieldKey: const ValueKey('job-field'),
            controller: _job,
            hint: _typing ? 'Barista, City Cafe' : '',
            minLines: 2,
            autofocus: _typing && _job.text.isEmpty,
            onChanged: (_) => setState(() {}),
          ),
        ];
      case _Phase.unheard:
        return const [ProblemNote(title: "We couldn't hear that.", body: 'Speak up, or type it.', centered: true)];
      case _Phase.micOff:
        return [
          ProblemNote(
            centered: true,
            title: _micFailed ? "The microphone didn't start." : 'The microphone is off.',
            body: _micFailed
                ? _speechError ?? 'Try again, or type it.'
                : _micBlocked
                    ? 'Allow it in Settings, or type it.'
                    : 'Allow it when you try again, or type it.',
          ),
        ];
      case _Phase.loading:
        return [AnswerQuote(_job.text.trim(), semanticPrefix: 'Your job')];
      case _Phase.error:
        return [
          ProblemNote(
            centered: true,
            title: "Couldn't get your questions.",
            body: _error?.userMessage ?? 'Something went wrong. Try again.',
          ),
        ];
    }
  }

  Widget _dock() {
    switch (_phase) {
      case _Phase.asking:
      case _Phase.ready:
      case _Phase.preparing:
      case _Phase.recording:
      case _Phase.transcribing:
      case _Phase.unheard:
        return _recordDock();
      case _Phase.settingUp:
        final setup = _services.speechSetup.state.value;
        return RecordDock(
          button: _SetupDial(setup: setup),
          status: Semantics(
            liveRegion: true,
            child: Text(setup.copying ? 'Setting up the voice on this phone' : 'Getting the voice ready'),
          ),
          leading: DockAction(
            icon: PrepIcons.keyboard,
            label: 'Type',
            semanticLabel: 'Type the job instead',
            onPressed: _typeInstead,
          ),
        );
      case _Phase.review:
        final voiceMissing = _services.speechSetup.state.value.missing;
        return PillDock(
          label: 'Use this',
          onPressed: _job.text.trim().isEmpty ? null : _submit,
          leading: _typing && voiceMissing
              ? null
              : DockAction(
                  icon: _typing ? PrepIcons.mic : PrepIcons.replay,
                  label: _typing ? 'Speak' : 'Retake',
                  semanticLabel: _typing ? 'Say it instead' : 'Record again',
                  onPressed: _record,
                ),
        );
      case _Phase.micOff:
        return PillDock(
          label: 'Type instead',
          icon: PrepIcons.keyboard,
          onPressed: _typeInstead,
          leading: DockAction(
            icon: _micBlocked ? PrepIcons.sliders : PrepIcons.replay,
            label: _micBlocked ? 'Open settings' : 'Try again',
            onPressed: _micBlocked ? _services.mic.openSettings : _record,
          ),
        );
      case _Phase.loading:
        return PillDock(label: 'Writing your questions', busy: true, onPressed: () {});
      case _Phase.error:
        return PillDock(
          label: 'Try again',
          onPressed: _submit,
          leading: DockAction(
            icon: PrepIcons.edit,
            label: 'Edit',
            semanticLabel: 'Change the job',
            onPressed: () => setState(() => _phase = _Phase.review),
          ),
        );
    }
  }

  /// The record dial with "Type" and "Repeat" beside it, and one line under it.
  Widget _recordDock() {
    final recording = _phase == _Phase.recording;
    final busy = _phase == _Phase.preparing || _phase == _Phase.transcribing;
    final Widget status = switch (_phase) {
      _Phase.recording => RecordClock(progress: _progress, limit: _maxJobRecording, big: true),
      _Phase.preparing => const Text('Getting ready'),
      _Phase.transcribing => const Text('Writing it down'),
      _Phase.unheard => const Text('Tap to try again'),
      _ => const Text('Tap to answer'),
    };
    return RecordDock(
      button: RecordButton(
        dial: true,
        recording: recording,
        progress: _progress,
        onPressed: busy ? null : (recording ? _stop : _record),
        semanticLabel: recording ? 'Stop recording' : 'Start recording the job',
      ),
      status: Semantics(liveRegion: !recording, child: status),
      level: recording ? _level : null,
      sidesVisible: !recording && !busy,
      leading: DockAction(
        icon: PrepIcons.keyboard,
        label: 'Type',
        semanticLabel: 'Type the job instead',
        onPressed: _typeInstead,
      ),
      trailing: DockAction(
        icon: PrepIcons.speaker,
        label: 'Repeat',
        semanticLabel: 'Hear the question again',
        onPressed: _phase == _Phase.ready || _phase == _Phase.unheard ? _ask : null,
      ),
    );
  }
}

/// First-launch set-up of the offline speech files, in the record dial's place: the ring fills
/// with the real progress, and the dial lights up once the voice is ready.
class _SetupDial extends StatelessWidget {
  const _SetupDial({required this.setup});

  final SpeechReadiness setup;

  @override
  Widget build(BuildContext context) {
    final percent = (setup.progress * 100).floor();
    return Semantics(
      label: setup.copying ? '$percent percent' : null,
      excludeSemantics: true,
      child: ArcGauge(
        value: setup.copying ? setup.progress : 0,
        size: RecordButton.dialExtent,
        ticks: true,
        stroke: 3,
        child: DecoratedBox(
          decoration: ShapeDecoration(color: PrepColors.surface2, shape: CircleBorder(side: BorderSide(color: PrepColors.rimLight))),
          child: SizedBox.square(
            dimension: RecordButton.dialDisc,
            child: Center(
              child: setup.copying
                  ? Text(
                      '$percent%',
                      style: PrepType.titleL.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    )
                  : PrepIcon(PrepIcons.mic, color: PrepColors.text3, size: 34),
            ),
          ),
        ),
      ),
    );
  }
}
