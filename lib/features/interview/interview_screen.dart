import 'dart:async';
import 'dart:math' as math;

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
import '../wrapup/wrapup_screen.dart';
import 'ask_coach_panel.dart';
import 'feedback_view.dart';
import 'read_aloud.dart';

const _maxAnswer = Duration(minutes: 2);

enum _Phase { speaking, ready, preparing, recording, transcribing, review, unheard, typing, micOff, checking, error, feedback }

/// Step two: one question at a time. The interviewer asks, the person answers out loud (up to
/// two minutes), and the coach comes back with short, blunt feedback on what went wrong.
class InterviewScreen extends StatefulWidget {
  const InterviewScreen({super.key, required this.session});

  final PracticeSession session;

  @override
  State<InterviewScreen> createState() => _InterviewScreenState();
}

class _InterviewScreenState extends State<InterviewScreen> with WidgetsBindingObserver {
  late AppServices _services;
  final _question = RevealController();
  final _level = LevelMix();
  final _progress = ValueNotifier<double>(0);
  final _elapsed = ValueNotifier<int>(0);
  final _typed = TextEditingController();
  final _scroll = ScrollController();
  final _panelKey = GlobalKey();
  StreamSubscription<String>? _partialSub;
  Timer? _ticker;

  /// Norman reading the feedback and the coach's answers (the question is read by [_ask]).
  late final ReadAloud _read;
  late final AskCoachController _asker;
  bool _wired = false;

  int _index = 0;
  _Phase _phase = _Phase.speaking;
  String _partial = '';
  String _transcript = '';
  DeliveryMetrics? _metrics;
  bool _wasTyped = false;
  bool _micBlocked = false;
  bool _micFailed = false;
  AnswerFeedback? _feedback;
  CoachException? _error;
  int _operation = 0;
  bool _closing = false;
  bool _leaving = false;
  String? _speechError;

  PracticeSession get _session => widget.session;
  CoachQuestion get _current => _session.questions[_index];
  bool get _isLast => _index >= _session.questions.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (!_wired) {
      _wired = true;
      _read = ReadAloud(_services.voice)..addListener(_changed);
      _asker = AskCoachController(
        services: _services,
        voice: _read,
        preferTyping: _session.preferTyping,
        mayReadAloud: () => _mayReadAloud,
      )..addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Norman reads feedback and answers out on his own only in spoken sessions, with the app in
  /// front, and not over a screen reader that is already reading the same words.
  bool get _mayReadAloud {
    if (_session.preferTyping || !mounted) return false;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life == AppLifecycleState.hidden || life == AppLifecycleState.paused || life == AppLifecycleState.detached) return false;
    return !MediaQuery.accessibleNavigationOf(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _operation++;
    _ticker?.cancel();
    _partialSub?.cancel();
    _read.removeListener(_changed);
    _asker.removeListener(_changed);
    _asker.dispose();
    _read.dispose();
    _services.voice.stop();
    _services.speech.cancel();
    _question.dispose();
    _level.dispose();
    _progress.dispose();
    _elapsed.dispose();
    _typed.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _ask() async {
    final operation = ++_operation;
    final text = _current.text;
    _question.start(text);
    _feedback = null;
    _error = null;
    _partial = '';
    _toTop();
    if (_session.preferTyping) {
      _question.showAll();
      setState(() => _phase = _Phase.typing);
      return;
    }
    setState(() => _phase = _Phase.speaking);
    try {
      await _services.voice.speak(text);
    } catch (_) {
      // The question is on screen even if the voice fails.
    }
    if (!mounted || operation != _operation) return;
    _question.showAll();
    _level.rest();
    if (_phase == _Phase.speaking) setState(() => _phase = _Phase.ready);
  }

  Future<void> _record() async {
    if (_phase == _Phase.recording) return _stop();
    if (_phase == _Phase.preparing || _phase == _Phase.transcribing || _phase == _Phase.checking) return;
    final operation = ++_operation;
    setState(() {
      _phase = _Phase.preparing;
      _speechError = null;
    });
    _question.showAll();
    try {
      await _read.hush();
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
      final started = await _services.speech.start(maxDuration: _maxAnswer);
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
    _elapsed.value = 0;
    _progress.value = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _elapsed.value += 100;
      _progress.value = _elapsed.value / _maxAnswer.inMilliseconds;
      if (_elapsed.value >= _maxAnswer.inMilliseconds) _stop();
    });
    setState(() {
      _partial = '';
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
    _transcript = heard;
    _metrics = result!.metrics;
    _wasTyped = false;
    _typed.text = heard;
    setState(() => _phase = _Phase.review);
  }

  Future<void> _confirmTranscript() async {
    final edited = _typed.text.trim();
    if (edited.isEmpty) return;
    if (edited != _transcript) {
      // Pace and filler counts were computed against the original transcript.
      // A correction is useful content, but isn't a newly measured recording.
      _metrics = null;
      _wasTyped = true;
    }
    _transcript = edited;
    FocusScope.of(context).unfocus();
    await _check();
  }

  void _typeInstead() {
    _operation++;
    unawaited(_read.hush());
    _question.showAll();
    setState(() => _phase = _Phase.typing);
  }

  Future<void> _sendTyped() async {
    final text = _typed.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    _transcript = text;
    _metrics = null;
    _wasTyped = true;
    await _check();
  }

  Future<void> _check() async {
    if (_phase == _Phase.checking) return;
    final operation = ++_operation;
    setState(() {
      _error = null;
      _phase = _Phase.checking;
    });
    try {
      final feedback = await _services.coach.feedback(
        job: _session.job,
        question: _current.text,
        transcript: _transcript,
        delivery: _metrics,
      );
      if (!mounted || operation != _operation) return;
      _session.answers[_index] = AnswerRecord(transcript: _transcript, metrics: _metrics, feedback: feedback, typed: _wasTyped);
      _asker.close();
      setState(() {
        _feedback = feedback;
        _phase = _Phase.feedback;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _toTop());
      // Said once as it arrives; "Hear feedback" plays it again.
      if (_mayReadAloud) unawaited(_read.say(Spoken.feedback, spokenFeedback(feedback)));
    } on CoachException catch (e) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _error = e;
        _phase = _Phase.error;
      });
    } catch (e) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _error = CoachException(CoachErrorKind.badResponse, message: '$e');
        _phase = _Phase.error;
      });
    }
  }

  void _tryAgain() {
    _asker.close();
    unawaited(_read.hush());
    _typed.clear();
    _toTop();
    setState(() {
      _feedback = null;
      _phase = _session.preferTyping ? _Phase.typing : _Phase.ready;
    });
  }

  void _toggleFeedback() {
    if (_read.current == Spoken.feedback) {
      unawaited(_read.hush());
      return;
    }
    final feedback = _feedback;
    if (feedback == null || _asker.usingMic) return;
    unawaited(_read.say(Spoken.feedback, spokenFeedback(feedback)));
  }

  void _openAsk() {
    _asker.open(AskTopic(job: _session.job, question: _current.text, answer: _transcript, feedback: _feedback));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final panel = _panelKey.currentContext;
      if (!mounted || panel == null) return;
      Scrollable.ensureVisible(
        panel,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.enter,
        curve: Motion.standard,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  Future<void> _next() async {
    if (_leaving || _phase != _Phase.feedback) return;
    // Norman stops mid-sentence rather than talking over the next question.
    _asker.close();
    unawaited(_read.hush());
    if (_isLast) {
      _leaving = true;
      await _services.sessions.finished(_session);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => WrapupScreen(session: _session)),
      );
      return;
    }
    _typed.clear();
    setState(() => _index++);
    await _ask();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    final busy = _session.answers.isNotEmpty || _phase == _Phase.recording || _phase == _Phase.checking;
    if (busy) {
      final end = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: PrepColors.surface2,
          title: Text('End this practice?', style: PrepType.titleM),
          content: Text('Your answers will be lost.', style: PrepType.body),
          actions: [
            QuietButton('Keep going', onPressed: () => Navigator.of(context).pop(false)),
            QuietButton('End practice', color: PrepColors.danger, onPressed: () => Navigator.of(context).pop(true)),
          ],
        ),
      );
      if (end != true || !mounted) {
        _closing = false;
        return;
      }
    }
    _operation++;
    _ticker?.cancel();
    _asker.close();
    await _read.hush();
    await _services.speech.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused && state != AppLifecycleState.detached) return;
    unawaited(_read.hush());
    _asker.pause();
    if (_phase == _Phase.recording) {
      unawaited(_stop());
    } else if (_phase == _Phase.preparing || _phase == _Phase.speaking) {
      _operation++;
      _services.speech.cancel();
      _question.showAll();
      setState(() => _phase = _Phase.ready);
    }
  }

  /// Larger while the interviewer asks and listens; smaller once there is text to read or edit.
  double _presenceSize(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return switch (_phase) {
      _Phase.speaking || _Phase.ready || _Phase.preparing || _Phase.recording =>
        math.min(screen.width * 0.8, screen.height * 0.28).clamp(152.0, 320.0),
      _Phase.feedback => 112,
      _ => 152,
    };
  }

  @override
  Widget build(BuildContext context) {
    final total = _session.questions.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CoachScaffold(
        status: 'Question ${_index + 1} of $total · ${_session.jobTitle}',
        presenceSize: _presenceSize(context),
        level: _level,
        onClose: _close,
        body: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _phase == _Phase.feedback ? _feedbackContent() : _answerContent(),
          ),
        ),
      ),
    );
  }

  List<Widget> _feedbackContent() {
    final feedback = _feedback!;
    final canHear = _asker.voiceAvailable && spokenFeedback(feedback).isNotEmpty;
    return [
      FeedbackView(
        question: _current.text,
        feedback: feedback,
        typed: _wasTyped,
        listen: canHear
            ? ReadAloudButton(
                label: 'Hear feedback',
                stopLabel: 'Stop reading the feedback',
                speaking: _read.current == Spoken.feedback,
                // Never read aloud into an open microphone.
                onPressed: _asker.usingMic ? null : _toggleFeedback,
              )
            : null,
      ),
      if (_asker.isOpen) ...[
        const SizedBox(height: Space.x3),
        AskCoachPanel(key: _panelKey, controller: _asker, voice: _read),
      ],
      const SizedBox(height: Space.x3),
      PrimaryButton(_isLast ? 'See your notes' : 'Next question', onPressed: _next),
      const SizedBox(height: Space.s),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          QuietButton('Try this one again', icon: PrepIcons.replay, onPressed: _tryAgain),
          if (!_asker.isOpen) QuietButton('Ask the coach', icon: PrepIcons.chat, onPressed: _openAsk),
        ],
      ),
    ];
  }

  List<Widget> _answerContent() {
    return [
      if (_session.set.mock) ...[
        Text('Sample questions', style: PrepType.meta),
        const SizedBox(height: Space.s),
      ],
      RevealText(controller: _question, style: PrepType.question),
      const SizedBox(height: Space.xxl),
      ..._phaseContent(),
    ];
  }

  List<Widget> _phaseContent() {
    switch (_phase) {
      // Ready and recording share one layout, so the record button never moves under a finger.
      case _Phase.speaking:
      case _Phase.ready:
      case _Phase.recording:
        final recording = _phase == _Phase.recording;
        return [
          Center(child: RecordButton(recording: recording, progress: _progress, onPressed: recording ? _stop : _record)),
          const SizedBox(height: Space.m),
          SizedBox(
            height: 26,
            child: Center(
              child: recording
                  ? ValueListenableBuilder<int>(
                      valueListenable: _elapsed,
                      builder: (context, ms, _) => Text.rich(
                        TextSpan(children: [
                          TextSpan(text: clock(ms), style: PrepType.timer),
                          TextSpan(text: '  / 2:00', style: PrepType.meta),
                        ]),
                      ),
                    )
                  : Text('Up to 2 minutes', style: PrepType.meta),
            ),
          ),
          const SizedBox(height: Space.m),
          if (recording)
            Text(
              _partial.isEmpty ? 'Listening' : _tail(_partial),
              style: PrepType.bodyL.copyWith(color: _partial.isEmpty ? PrepColors.text3 : PrepColors.text2),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                QuietButton('Hear it again', icon: PrepIcons.replay, onPressed: _phase == _Phase.ready ? _ask : null),
                QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: _typeInstead),
              ],
            ),
        ];
      case _Phase.transcribing:
        return const [LoadingLine('Turning your answer into text')];
      case _Phase.preparing:
        return const [LoadingLine('Preparing microphone')];
      case _Phase.review:
        return [
          PrepTextField(
            fieldKey: const ValueKey('answer-review-field'),
            controller: _typed,
            hint: 'Your recorded answer',
            minLines: 4,
            maxLines: 10,
            onChanged: (_) => setState(() {}),
          ),
          if (_typed.text.trim() != _transcript) ...[
            const SizedBox(height: Space.s),
            Text('Edited text gets no voice feedback.', style: PrepType.meta),
          ],
          const SizedBox(height: Space.xxl),
          PrimaryButton('Get feedback', onPressed: _typed.text.trim().isEmpty ? null : _confirmTranscript),
          const SizedBox(height: Space.s),
          Center(child: QuietButton('Record again', icon: PrepIcons.replay, onPressed: _record)),
        ];
      case _Phase.unheard:
        return [
          const ProblemNote(
            title: "We couldn't hear your answer.",
            body: 'Speak up, or type it.',
          ),
          const SizedBox(height: Space.xxl),
          Center(child: RecordButton(recording: false, progress: _progress, onPressed: _record)),
          const SizedBox(height: Space.s),
          Center(child: QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: _typeInstead)),
        ];
      case _Phase.typing:
        return [
          PrepTextField(
            fieldKey: const ValueKey('answer-field'),
            controller: _typed,
            hint: 'Type your answer the way you would say it.',
            minLines: 4,
            maxLines: 10,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.xxl),
          PrimaryButton('Send answer', onPressed: _typed.text.trim().isEmpty ? null : _sendTyped),
          const SizedBox(height: Space.s),
          Center(child: QuietButton('Answer out loud instead', icon: PrepIcons.mic, onPressed: _record)),
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
      case _Phase.checking:
        return [
          Text(
            '“${_tail(_transcript, 220)}”',
            style: PrepType.quote.copyWith(color: PrepColors.text2),
          ),
          const SizedBox(height: Space.xxl),
          const LoadingLine('Checking your answer'),
        ];
      case _Phase.error:
        return [
          ProblemNote(title: "Couldn't check your answer.", body: _error?.userMessage ?? 'Something went wrong. Try again.'),
          const SizedBox(height: Space.xxl),
          PrimaryButton('Try again', onPressed: _check),
          const SizedBox(height: Space.s),
          Center(child: QuietButton('Answer again', icon: PrepIcons.replay, onPressed: _tryAgain)),
        ];
      case _Phase.feedback:
        return const [];
    }
  }

  static String _tail(String text, [int max = 260]) {
    if (text.length <= max) return text;
    final cut = text.substring(text.length - max);
    final space = cut.indexOf(' ');
    return '…${space > 0 ? cut.substring(space + 1) : cut}';
  }
}
