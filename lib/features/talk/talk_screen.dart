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
import '../../design/glass.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/robot_stage.dart';
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

  /// On the turn's view, so a new turn can be scrolled to its start.
  final key = GlobalKey();
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
    _scrollToTurn(turn);
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
      _scrollToTurn(turn);
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
      _scrollToTurn(turn);
    } catch (e) {
      if (!mounted || operation != _operation) return;
      setState(() {
        turn.error = CoachException(CoachErrorKind.badResponse, message: '$e');
        _asking = false;
        _mood = AssistantMood.idle;
      });
      _scrollToTurn(turn);
    }
  }

  /// Shows a turn from its question down, so a long answer reads from its start (the dock stays
  /// one scroll away). Falls back to the end when the turn is not laid out yet.
  void _scrollToTurn(_Turn turn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = turn.key.currentContext;
      final duration = _still ? Duration.zero : Motion.enter;
      if (target == null) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: duration, curve: Motion.standard);
        return;
      }
      Scrollable.ensureVisible(target, duration: duration, curve: Motion.standard);
    });
  }

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AssistantLook>(
      valueListenable: _services.assistant,
      builder: (context, look, _) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
        return AmbientBackdrop(
          child: Scaffold(
            backgroundColor: const Color(0x00000000),
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(title: 'Talk to ${look.name}', onBack: () => Navigator.of(context).maybePop()),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // Big on its lit floor until the conversation needs the room.
                        final h = box.maxHeight;
                        var size = keyboard ? h * 0.18 : (_turns.isEmpty ? h * 0.46 : h * 0.26);
                        size = math.min(size, box.maxWidth * (_turns.isEmpty ? 0.9 : 0.6));
                        if (size < 64) size = 0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(end: size),
                              duration: _still ? Duration.zero : Motion.enter,
                              curve: Motion.standard,
                              // Never taller than the room (the keyboard can take it mid-animation).
                              builder: (context, t, _) {
                                final s = math.min(t, h);
                                return SizedBox(
                                  height: s,
                                  child: s < 1
                                      ? null
                                      : Center(
                                          child: RobotStage(look: look, robotSize: s, mood: _mood, level: _activeLevel),
                                        ),
                                );
                              },
                            ),
                            Expanded(
                              child: CustomScrollView(
                                controller: _scroll,
                                slivers: [
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
                                    sliver: _turns.isEmpty
                                        ? SliverToBoxAdapter(child: _SuggestionChips(onTap: _ask))
                                        : SliverList.builder(
                                            itemCount: _turns.length,
                                            itemBuilder: (context, i) => _TurnView(
                                              key: _turns[i].key,
                                              turn: _turns[i],
                                              name: look.name,
                                              onRetry: () => _retry(_turns[i]),
                                            ),
                                          ),
                                  ),
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, Space.l),
                                        child: _inputArea(),
                                      ),
                                    ),
                                  ),
                                ],
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
          ),
        );
      },
    );
  }

  Widget _inputArea() {
    switch (_recordState) {
      case _RecordState.preparing:
        return const _Status('Getting the mic ready');
      case _RecordState.transcribing:
        return const _Status('Writing it down');
      case _RecordState.unheard:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Note(title: "Couldn't hear that.", body: 'Speak up, or type it.'),
            const SizedBox(height: Space.l),
            _voiceRow(),
          ],
        );
      case _RecordState.micOff:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Note(
              title: _micFailed ? "The mic didn't start." : 'The mic is off.',
              body: _micFailed
                  ? _speechError ?? 'Try again, or type it.'
                  : _micBlocked
                  ? 'Allow it in Settings, or type it.'
                  : 'Allow it when you try again, or type it.',
            ),
            const SizedBox(height: Space.m),
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

  /// Voice first: the record disc in the middle (its ring counts down the 15 seconds), typing on
  /// the left, the time on the right. The words heard so far show above it while recording.
  Widget _voiceRow() {
    final recording = _recordState == _RecordState.recording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recording)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _partial.isEmpty ? 'Listening' : _partial,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: PrepType.bodyL.copyWith(color: _partial.isEmpty ? PrepColors.text3 : PrepColors.text),
              ),
            ),
          ),
        Builder(
          // The dock spans the screen between the gutters (no LayoutBuilder: the sliver around it asks
          // for its intrinsic height).
          builder: (context) {
            final width = MediaQuery.sizeOf(context).width - Space.gutter * 2;
            final type = QuietButton(
              'Type instead',
              icon: PrepIcons.keyboard,
              onPressed: _asking || recording ? null : _typeInstead,
            );
            final button = RecordButton(
              recording: recording,
              countdown: true,
              progress: _progress,
              onPressed: _asking ? null : (recording ? _stopRecording : _startRecording),
            );
            final time = recording
                ? ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (context, p, _) {
                      final left = ((1 - p.clamp(0.0, 1.0)) * _maxTalkRecording.inSeconds).ceil();
                      return Text('${left}s left', textAlign: TextAlign.center, style: PrepType.label);
                    },
                  )
                : Text('15 seconds', textAlign: TextAlign.center, style: PrepType.meta);
            final side = (width - 96) / 2 - Space.s;
            // Large text or a narrow phone: the record disc alone on its line, the rest under it.
            if (!_fitsBeside(context, 'Type instead', side)) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [button, const SizedBox(height: Space.s), time, const SizedBox(height: Space.xs), type],
              );
            }
            return Row(
              children: [
                Expanded(child: Align(alignment: Alignment.centerLeft, child: type)),
                button,
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(padding: const EdgeInsets.only(right: Space.m), child: time),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Typing: a metal field, then Send (the one accent) with speaking one tap away.
  Widget _typingRow() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetalCard(
          radius: Radii.sheet,
          padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.l),
          child: TextField(
            key: const ValueKey('talk-field'),
            controller: _typed,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendTyped(),
            style: PrepType.bodyL,
            cursorColor: PrepColors.accent,
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Ask anything',
              hintStyle: PrepType.bodyL.copyWith(color: PrepColors.text3),
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _typed,
          builder: (context, value, _) => Row(
            children: [
              Expanded(
                child: Center(
                  child: QuietButton('Speak instead', icon: PrepIcons.mic, onPressed: _asking ? null : _speakInstead),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: PrimaryButton('Send', onPressed: _asking || value.text.trim().isEmpty ? null : _sendTyped),
              ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.gutter, Space.s),
      child: Row(
        children: [
          MetalDisc(PrepIcons.back, label: 'Back', onPressed: onBack, size: 48),
          const SizedBox(width: Space.l),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: PrepType.titleM, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three ready-made questions as metal chips, shown only until the first turn.
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
      children: [
        for (final s in _suggestions)
          MetalTile(
            semanticLabel: s,
            onTap: () => onTap(s),
            radius: Radii.sheet,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Text(s, style: PrepType.label.copyWith(color: PrepColors.text2)),
          ),
      ],
    );
  }
}

/// Their question in the accent at the right, then the coach's answer on metal at the left (or
/// its thinking or error state).
class _TurnView extends StatelessWidget {
  const _TurnView({super.key, required this.turn, required this.name, required this.onRetry});

  final _Turn turn;
  final String name;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = turn.error;
    final answer = turn.answer;
    final Widget reply;
    if (error != null) {
      reply = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Note(title: "Couldn't get an answer.", body: error.userMessage),
          const SizedBox(height: Space.xs),
          Transform.translate(
            offset: const Offset(-Space.m, 0),
            child: QuietButton('Try again', icon: PrepIcons.replay, onPressed: onRetry),
          ),
        ],
      );
    } else if (answer == null) {
      reply = Semantics(
        liveRegion: true,
        label: '$name is thinking',
        excludeSemantics: true,
        child: Text('Thinking', style: PrepType.bodyL.copyWith(color: PrepColors.text3)),
      );
    } else {
      reply = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turn.mock) ...[
            Text('Sample answer', style: PrepType.meta),
            const SizedBox(height: Space.xs),
          ],
          Text(answer, style: PrepType.bodyL),
        ],
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.82),
              child: Semantics(
                label: 'You: ${turn.question}',
                excludeSemantics: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: PrepColors.accent, borderRadius: BorderRadius.circular(Radii.card)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: Space.m),
                    child: Text(turn.question, style: PrepType.bodyL.copyWith(color: PrepColors.onAccent)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.m),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.88),
              child: MetalCard(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), child: reply),
            ),
          ),
        ],
      ),
    );
  }
}

/// A problem said plainly: a warning mark, what happened, what to do.
class _Note extends StatelessWidget {
  const _Note({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PrepIcon(PrepIcons.close, color: PrepColors.warning, size: 18),
              const SizedBox(width: Space.s),
              Expanded(child: Text(title, style: PrepType.titleM.copyWith(color: PrepColors.warning))),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(body, style: PrepType.body),
        ],
      ),
    );
  }
}

/// What is happening while the mic gets ready or the words are written down.
class _Status extends StatelessWidget {
  const _Status(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center, style: PrepType.bodyLMedium.copyWith(color: PrepColors.text2)),
          const SizedBox(height: Space.m),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(2)),
            child: LinearProgressIndicator(minHeight: 2, color: PrepColors.accent, backgroundColor: PrepColors.line),
          ),
        ],
      ),
    );
  }
}

/// Whether [label] fits on one line in [width] beside the mic, with its icon and padding.
bool _fitsBeside(BuildContext context, String label, double width, {bool icon = true}) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: PrepType.label),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final needed = painter.width + Space.m * 2 + (icon ? 18 + Space.s : 0);
  painter.dispose();
  return needed <= width;
}
