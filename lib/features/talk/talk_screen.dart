import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/services.dart';
import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../coach/speech_adapter.dart' show speechErrorMessage;
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';
import '../interview/read_aloud.dart' show speakable;

/// The longest a spoken question to the assistant may run for.
const _maxTalkRecording = Duration(seconds: 15);

enum _RecordState { idle, preparing, recording, transcribing, unheard, micOff }

enum _InputMode { voice, typing }

/// One question and its answer. Kept mutable so a retry updates it in place instead of growing
/// the conversation with a duplicate.
class _Turn {
  _Turn(this.question);

  final String question;
  String? answer;
  bool mock = false;
  CoachException? error;
}

/// A voice conversation with the chosen assistant: ask anything, out loud or typed, and it
/// answers in the interviewer's voice while its face follows along (listening, thinking,
/// speaking). Every await is guarded by [mounted] and an operation counter, so a late microphone
/// or coach result from a closed screen can never change it.
class TalkScreen extends StatefulWidget {
  const TalkScreen({super.key});

  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> with WidgetsBindingObserver {
  late AppServices _services;
  final _micLevel = LevelMix();
  final _voiceLevel = LevelMix();
  final _typed = TextEditingController();
  final _progress = ValueNotifier<double>(0);
  final _scroll = ScrollController();
  final List<_Turn> _turns = [];
  StreamSubscription<String>? _partialSub;
  Timer? _ticker;

  AssistantMood _mood = AssistantMood.happy;
  _RecordState _recordState = _RecordState.idle;
  _InputMode _inputMode = _InputMode.voice;
  String _partial = '';
  bool _micBlocked = false;
  bool _micFailed = false;
  String? _speechError;
  bool _asking = false;
  int _operation = 0;
  bool _started = false;

  /// The voice level that should drive the assistant's face for the current mood.
  ValueListenable<double>? get _activeLevel => switch (_mood) {
    AssistantMood.listening => _micLevel,
    AssistantMood.speaking => _voiceLevel,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _started) return;
      _started = true;
      _micLevel.listenTo(_services.speech.level);
      _voiceLevel.listenTo(_services.voice.level);
      _partialSub = _services.speech.partialText.listen((text) {
        if (mounted && _recordState == _RecordState.recording) setState(() => _partial = text);
      });
      _greet();
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
    _services.voice.stop();
    _services.speech.cancel();
    _micLevel.dispose();
    _voiceLevel.dispose();
    _typed.dispose();
    _progress.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused && state != AppLifecycleState.detached) return;
    _operation++;
    _services.voice.stop();
    if (_recordState == _RecordState.recording || _recordState == _RecordState.preparing) {
      _ticker?.cancel();
      _services.speech.cancel();
      setState(() {
        _recordState = _RecordState.idle;
        _mood = AssistantMood.idle;
      });
    }
  }

  /// Says hello once: a brief happy look, then the greeting plays with a speaking mouth. A voice
  /// that fails to play is not a reason to stop; the screen works from text alone.
  Future<void> _greet() async {
    final operation = ++_operation;
    final name = _services.assistant.value.name;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || operation != _operation) return;
    setState(() => _mood = AssistantMood.speaking);
    try {
      await _services.voice.speak("Hi, I'm $name. Ask me anything about your interview.");
    } catch (_) {
      // Silent assistant: the screen still works from typing.
    }
    if (!mounted || operation != _operation) return;
    setState(() => _mood = AssistantMood.idle);
  }

  Future<void> _startRecording() async {
    if (_recordState == _RecordState.recording) {
      await _stopRecording();
      return;
    }
    if (_recordState == _RecordState.preparing || _recordState == _RecordState.transcribing || _asking) return;
    final operation = ++_operation;
    setState(() {
      _recordState = _RecordState.preparing;
      _speechError = null;
    });
    try {
      await _services.voice.stop();
      if (!mounted || operation != _operation) return;
      final access = await _services.mic.request();
      if (!mounted || operation != _operation) return;
      if (access != MicAccess.granted) {
        setState(() {
          _micBlocked = access == MicAccess.blocked;
          _micFailed = false;
          _recordState = _RecordState.micOff;
        });
        return;
      }
      final started = await _services.speech.start(maxDuration: _maxTalkRecording);
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
        _recordState = _RecordState.micOff;
      });
      return;
    }
    var elapsed = 0;
    _progress.value = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed += 100;
      _progress.value = elapsed / _maxTalkRecording.inMilliseconds;
      if (elapsed >= _maxTalkRecording.inMilliseconds) _stopRecording();
    });
    setState(() {
      _partial = '';
      _recordState = _RecordState.recording;
      _mood = AssistantMood.listening;
    });
  }

  Future<void> _stopRecording() async {
    if (_recordState != _RecordState.recording) return;
    final operation = _operation;
    _ticker?.cancel();
    setState(() {
      _recordState = _RecordState.transcribing;
      _mood = AssistantMood.thinking;
    });
    CaptureResult? result;
    try {
      result = await _services.speech.stop();
    } catch (_) {
      result = null;
    }
    if (!mounted || operation != _operation) return;
    _micLevel.rest();
    final heard = result?.transcript.text.trim() ?? '';
    if (heard.isEmpty) {
      setState(() {
        _recordState = _RecordState.unheard;
        _mood = AssistantMood.idle;
      });
      return;
    }
    setState(() => _recordState = _RecordState.idle);
    await _ask(heard);
  }

  void _typeInstead() => setState(() => _inputMode = _InputMode.typing);

  void _speakInstead() => setState(() => _inputMode = _InputMode.voice);

  void _sendTyped() {
    final text = _typed.text.trim();
    if (text.isEmpty || _asking) return;
    _typed.clear();
    FocusScope.of(context).unfocus();
    _ask(text);
  }

  Future<void> _ask(String question) async {
    if (_asking) return;
    await _services.voice.stop();
    if (!mounted) return;
    final turn = _Turn(question);
    setState(() => _turns.add(turn));
    _scrollToEnd();
    await _run(turn);
  }

  Future<void> _retry(_Turn turn) async {
    if (_asking) return;
    setState(() => turn.error = null);
    await _run(turn);
  }

  Future<void> _run(_Turn turn) async {
    final operation = ++_operation;
    setState(() {
      _asking = true;
      _mood = AssistantMood.thinking;
    });
    try {
      final profile = _services.profile.value;
      final reply = await _services.coach.ask(
        job: profile.targetRole,
        userQuestion: turn.question,
        about: profile.about,
      );
      if (!mounted || operation != _operation) return;
      setState(() {
        turn.answer = reply.answer;
        turn.mock = reply.mock;
        _asking = false;
        _mood = AssistantMood.speaking;
      });
      _scrollToEnd();
      try {
        await _services.voice.speak(speakable(reply.answer));
      } catch (_) {
        // Keep the answer on screen even when it can't be read aloud.
      }
      if (!mounted || operation != _operation) return;
      setState(() => _mood = AssistantMood.idle);
    } on CoachException catch (e) {
      if (!mounted || operation != _operation) return;
      setState(() {
        turn.error = e;
        _asking = false;
        _mood = AssistantMood.idle;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted || operation != _operation) return;
      setState(() {
        turn.error = CoachException(CoachErrorKind.badResponse, message: '$e');
        _asking = false;
        _mood = AssistantMood.idle;
      });
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.enter, curve: Motion.standard);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AssistantLook>(
      valueListenable: _services.assistant,
      builder: (context, look, _) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
        return Scaffold(
          backgroundColor: PrepColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(title: 'Talk to ${look.name}', onBack: () => Navigator.of(context).maybePop()),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final size = math
                          .min(
                            box.maxWidth * (_turns.isEmpty ? 0.78 : 0.4),
                            box.maxHeight * (keyboard ? 0.15 : (_turns.isEmpty ? 0.42 : 0.25)),
                          )
                          .clamp(0.0, _turns.isEmpty ? 360.0 : 170.0);
                      return CustomScrollView(
                        controller: _scroll,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(top: Space.s, bottom: Space.m),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(end: size),
                                duration: Motion.enter,
                                curve: Motion.standard,
                                builder: (context, currentSize, _) => Center(
                                  child: AssistantAvatar(
                                    look: look,
                                    size: currentSize,
                                    mood: _mood,
                                    level: _activeLevel,
                                    hud: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
                            sliver: _turns.isEmpty
                                ? SliverToBoxAdapter(child: _SuggestionChips(onTap: _ask))
                                : SliverList.builder(
                                    itemCount: _turns.length,
                                    itemBuilder: (context, i) =>
                                        _TurnView(turn: _turns[i], onRetry: () => _retry(_turns[i])),
                                  ),
                          ),
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
                                child: _inputArea(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _inputArea() {
    switch (_recordState) {
      case _RecordState.preparing:
        return const LoadingLine('Preparing microphone');
      case _RecordState.transcribing:
        return const LoadingLine('Turning your question into text');
      case _RecordState.unheard:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ProblemNote(title: "We couldn't hear that.", body: 'Speak up, or type it.'),
            const SizedBox(height: Space.l),
            _voiceRow(),
          ],
        );
      case _RecordState.micOff:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProblemNote(
              title: _micFailed ? "The microphone didn't start." : 'The microphone is off.',
              body: _micFailed
                  ? _speechError ?? 'Try again, or type it.'
                  : _micBlocked
                  ? 'Allow it in Settings, or type it.'
                  : 'Allow it when you try again, or type it.',
            ),
            const SizedBox(height: Space.l),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: _typeInstead),
                QuietButton(
                  _micBlocked ? 'Open settings' : 'Try again',
                  onPressed: _micBlocked ? _services.mic.openSettings : _startRecording,
                ),
              ],
            ),
          ],
        );
      case _RecordState.idle:
      case _RecordState.recording:
        return _inputMode == _InputMode.typing ? _typingRow() : _voiceRow();
    }
  }

  Widget _voiceRow() {
    final recording = _recordState == _RecordState.recording;
    return Column(
      children: [
        Center(
          child: RecordButton(
            recording: recording,
            countdown: true,
            progress: _progress,
            onPressed: _asking ? null : (recording ? _stopRecording : _startRecording),
          ),
        ),
        const SizedBox(height: Space.m),
        Center(
          child: recording
              ? ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, p, _) {
                    final left = ((1 - p.clamp(0.0, 1.0)) * _maxTalkRecording.inSeconds).ceil();
                    return Text('${left}s left', style: PrepType.meta);
                  },
                )
              : Text('15 seconds', style: PrepType.meta),
        ),
        const SizedBox(height: Space.s),
        if (recording)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: Text(
              _partial.isEmpty ? 'Listening' : _partial,
              textAlign: TextAlign.center,
              style: PrepType.bodyL.copyWith(color: _partial.isEmpty ? PrepColors.text3 : PrepColors.text),
            ),
          )
        else
          Center(
            child: QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: _asking ? null : _typeInstead),
          ),
      ],
    );
  }

  Widget _typingRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrepTextField(
          fieldKey: const ValueKey('talk-field'),
          controller: _typed,
          hint: 'Ask anything',
          minLines: 1,
          maxLines: 4,
          autofocus: true,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendTyped(),
        ),
        const SizedBox(height: Space.s),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _typed,
          builder: (context, value, _) => Wrap(
            alignment: WrapAlignment.center,
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              QuietButton(
                'Send',
                icon: PrepIcons.chat,
                onPressed: _asking || value.text.trim().isEmpty ? null : _sendTyped,
              ),
              QuietButton('Speak instead', icon: PrepIcons.mic, onPressed: _asking ? null : _speakInstead),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.gutter, Space.s),
        child: Row(
          children: [
            IconAction(PrepIcons.back, label: 'Back', plain: true, onPressed: onBack),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: PrepType.titleM, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three ready-made questions, shown only until the first turn starts the real conversation.
class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({required this.onTap});

  final ValueChanged<String> onTap;

  static const _suggestions = [
    "How do I answer 'Tell me about yourself'?",
    'How do I calm my nerves?',
    'What should I ask them?',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: Space.s,
      runSpacing: Space.s,
      children: [for (final s in _suggestions) _Chip(text: s, onTap: () => onTap(s))],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusRing(
      radius: Radii.chip,
      child: Material(
        color: PrepColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          focusColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
              child: Center(
                child: Text(text, style: PrepType.meta.copyWith(color: PrepColors.text2)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Their question as a quiet quote, then the answer (or its thinking/error state).
class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn, required this.onRetry});

  final _Turn turn;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('“${turn.question}”', style: PrepType.quote.copyWith(color: PrepColors.text2)),
          const SizedBox(height: Space.m),
          if (turn.error != null) ...[
            ProblemNote(title: "Couldn't get an answer.", body: turn.error!.userMessage),
            const SizedBox(height: Space.s),
            Transform.translate(
              offset: const Offset(-Space.m, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: QuietButton('Try again', icon: PrepIcons.replay, onPressed: onRetry),
              ),
            ),
          ] else if (turn.answer == null)
            const LoadingLine('The coach is thinking')
          else ...[
            if (turn.mock) ...[
              Text('Sample answer', style: PrepType.label.copyWith(color: PrepColors.accent)),
              const SizedBox(height: Space.xs),
            ],
            Text(turn.answer!, style: PrepType.bodyL),
          ],
        ],
      ),
    );
  }
}
