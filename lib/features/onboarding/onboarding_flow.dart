import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/profile.dart';
import '../../app/services.dart';
import '../../coach/coach_api.dart' show jobTitleFrom;
import '../../coach/contracts.dart';
import '../../design/assistant_avatar.dart';
import '../../design/assistant_picker.dart';
import '../../design/components.dart';
import '../../design/glass.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/practice_chrome.dart';
import '../../design/robot_stage.dart';
import '../../design/tokens.dart';

/// First run as a conversation. You pick how your coach looks, then it introduces itself out loud
/// and asks your name, the job and a little about you. You answer by voice first (one big mic), or
/// type instead. Privacy is asked later, before the first practice, where it matters.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Step { pick, name, job, about, done }

class _Line {
  const _Line(this.text, {required this.mine});

  final String text;
  final bool mine;
}

class _OnboardingFlowState extends State<OnboardingFlow> with WidgetsBindingObserver {
  late AppServices _services;
  final _level = LevelMix();
  final _field = TextEditingController();
  final _scroll = ScrollController();
  final _lines = <_Line>[];
  StreamSubscription<String>? _partialSub;
  _Step _step = _Step.pick;
  bool _speaking = false;
  bool _recording = false;
  bool _transcribing = false;
  String? _note;
  int _operation = 0;
  bool _started = false;

  /// The person chose the keyboard; voice stays one tap away on the mic.
  bool _prefersTyping = false;

  static const _steps = [_Step.pick, _Step.name, _Step.job, _Step.about];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
    if (_started) return;
    _started = true;
    _level.listenTo(_services.voice.level);
    _level.listenTo(_services.speech.level);
    _partialSub = _services.speech.partialText.listen((text) {
      if (mounted && _recording) setState(() => _field.text = text);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _operation++;
      _services.voice.stop();
      if (_recording) _services.speech.cancel();
      if (mounted) setState(() => _recording = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _operation++;
    _services.voice.stop();
    if (_recording) _services.speech.cancel();
    _partialSub?.cancel();
    _level.dispose();
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AssistantLook get _look => _services.assistant.value;
  Profile get _profile => _services.profile.value;

  AssistantMood get _mood {
    if (_recording) return AssistantMood.listening;
    if (_transcribing) return AssistantMood.thinking;
    if (_speaking) return AssistantMood.speaking;
    return switch (_step) {
      _Step.pick || _Step.done => AssistantMood.happy,
      _ => AssistantMood.idle,
    };
  }

  // -------------------------------------------------------------------------
  // The conversation
  // -------------------------------------------------------------------------

  /// The coach says [text]: it appears as a bubble and is spoken aloud.
  Future<void> _say(String text) async {
    final operation = ++_operation;
    setState(() {
      _lines.add(_Line(text, mine: false));
      _speaking = true;
    });
    _toBottom();
    try {
      await _services.voice.speak(text);
    } catch (_) {
      // No voice on this phone: the words are on screen.
    }
    if (!mounted || operation != _operation) return;
    _level.rest();
    setState(() => _speaking = false);
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.enter, curve: Motion.standard);
    });
  }

  Future<void> _begin() async {
    setState(() => _step = _Step.name);
    await _say("Hi, I'm ${_look.name}, your interview coach. What should I call you?");
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _field.text).trim();
    if (text.isEmpty || _recording || _transcribing) return;
    _operation++;
    unawaited(_services.voice.stop());
    FocusScope.of(context).unfocus();
    _field.clear();
    setState(() {
      _lines.add(_Line(text, mine: true));
      _note = null;
      _speaking = false;
    });
    _toBottom();
    switch (_step) {
      case _Step.name:
        await _save(_profile.copyWith(name: text));
        setState(() => _step = _Step.job);
        await _say('Nice to meet you, $text. What job are you preparing for?');
      case _Step.job:
        // A spoken answer is a sentence; keep the role itself as the job title.
        await _save(_profile.copyWith(targetRole: text.length > 40 ? jobTitleFrom(text) : text));
        setState(() => _step = _Step.about);
        await _say('Great. Now tell me about you: school, work, strengths.');
      case _Step.about:
        await _save(_profile.copyWith(about: text));
        await _wrapUp();
      default:
        break;
    }
  }

  Future<void> _skipAbout() async {
    _operation++;
    unawaited(_services.voice.stop());
    setState(() => _lines.add(const _Line('Not now', mine: true)));
    await _wrapUp();
  }

  Future<void> _wrapUp() async {
    setState(() => _step = _Step.done);
    final name = _profile.name.trim();
    await _say(name.isEmpty ? "All set. Let's practice!" : "All set, $name. Let's practice!");
  }

  Future<void> _finish() async {
    _operation++;
    await _services.voice.stop();
    await _services.assistant.finishOnboarding();
    widget.onDone();
  }

  Future<void> _skipAll() async {
    _operation++;
    await _services.voice.stop();
    if (_recording) await _services.speech.cancel();
    await _services.assistant.finishOnboarding();
    widget.onDone();
  }

  Future<void> _save(Profile profile) async {
    try {
      await _services.profile.save(profile);
    } catch (_) {
      // Worst case they add it later in Profile.
    }
  }

  // -------------------------------------------------------------------------
  // Talking instead of typing
  // -------------------------------------------------------------------------

  Future<void> _toggleMic() async {
    if (_transcribing) return;
    if (_recording) return _stopMic();
    final operation = ++_operation;
    await _services.voice.stop();
    setState(() {
      _speaking = false;
      _note = null;
    });
    final access = await _services.mic.request();
    if (!mounted || operation != _operation) return;
    if (access != MicAccess.granted) {
      setState(() {
        _prefersTyping = true;
        _note = access == MicAccess.blocked
            ? 'The mic is off. Type your answer.'
            : 'Allow the mic, or type your answer.';
      });
      return;
    }
    final max = _step == _Step.about ? const Duration(seconds: 45) : const Duration(seconds: 10);
    bool started;
    try {
      started = await _services.speech.start(maxDuration: max);
    } catch (_) {
      started = false;
    }
    if (!mounted || operation != _operation) {
      if (started) await _services.speech.cancel();
      return;
    }
    if (!started) {
      setState(() {
        _prefersTyping = true;
        _note = "The mic didn't start. Type your answer.";
      });
      return;
    }
    setState(() {
      _recording = true;
      _field.clear();
    });
    unawaited(
      Future<void>.delayed(max + const Duration(milliseconds: 300), () {
        if (mounted && operation == _operation && _recording) _stopMic();
      }),
    );
  }

  Future<void> _stopMic() async {
    if (!_recording) return;
    final operation = _operation;
    setState(() {
      _recording = false;
      _transcribing = true;
    });
    CaptureResult? result;
    try {
      result = await _services.speech.stop();
    } catch (_) {
      result = null;
    }
    if (!mounted || operation != _operation) return;
    _level.rest();
    final heard = result?.transcript.text.trim() ?? '';
    setState(() {
      _transcribing = false;
      if (heard.isEmpty) {
        _note = "I couldn't hear that. Try again, or type it.";
      } else {
        _field.text = heard;
        _field.selection = TextSelection.collapsed(offset: heard.length);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------------

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AssistantLook>(
      valueListenable: _services.assistant,
      builder: (context, look, _) => AmbientBackdrop(
        child: Scaffold(
          backgroundColor: const Color(0x00000000),
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  steps: _steps.length,
                  done: _step == _Step.done ? _steps.length : _steps.indexOf(_step),
                  onSkip: _skipAll,
                ),
                Expanded(child: _step == _Step.pick ? _pickView(look) : _chatView(look)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The coach on its own lit stage, about half the screen, with the four coaches as discs under
  /// it and Continue. Small screens and large text scroll instead of squeezing the stage.
  Widget _pickView(AssistantLook look) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(0.0, box.maxWidth - Space.gutter * 2);
        final header = [
          Semantics(header: true, child: Text('Choose your coach', style: PrepType.display)),
          const SizedBox(height: Space.xs),
          Text('Change it any time', style: PrepType.meta),
        ];
        final footer = [
          AssistantPicker(selected: look.kind, onSelected: _services.assistant.choose, showNames: false),
          const SizedBox(height: Space.xl),
          PrimaryButton('Continue', key: const ValueKey('onboarding-continue'), onPressed: _begin),
        ];
        const padding = EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.xl);
        final room = box.maxHeight - _pickChromeHeight(context, width);
        if (room >= 260) {
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...header,
                const SizedBox(height: Space.xl),
                Expanded(child: _stage(look)),
                const SizedBox(height: Space.xl),
                ...footer,
              ],
            ),
          );
        }
        final stage = (box.maxHeight * 0.8).clamp(220.0, 360.0);
        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...header,
              const SizedBox(height: Space.l),
              SizedBox(height: stage, child: _stage(look)),
              const SizedBox(height: Space.xl),
              ...footer,
            ],
          ),
        );
      },
    );
  }

  /// Everything on the picker but the stage, at the current width and text size, so the stage can
  /// take the rest.
  double _pickChromeHeight(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    double lines(String text, TextStyle style) {
      final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler)
        ..layout(maxWidth: width);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final perRow = ((width + Space.s) / (AssistantPicker.disc + Space.s)).floor().clamp(1, AssistantLook.all.length);
    final rows = (AssistantLook.all.length / perRow).ceil();
    final picker = rows * AssistantPicker.disc + (rows - 1) * Space.m;
    final button = math.max(56.0, lines('Continue', PrepType.button) + Space.m * 2);
    return Space.s +
        lines('Choose your coach', PrepType.display) +
        Space.xs +
        lines('Change it any time', PrepType.meta) +
        Space.xl * 3 +
        picker +
        button +
        Space.xl;
  }

  /// The hero: the chosen robot on its dial and pedestal inside one big metal card, its name under
  /// it like a plate. Changing coach crossfades.
  Widget _stage(AssistantLook look) {
    return MetalCard(
      hero: true,
      radius: Radii.sheet,
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xl),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final robot = math.max(0.0, math.min(box.maxHeight, box.maxWidth));
                final ratio = MediaQuery.devicePixelRatioOf(context);
                for (final other in AssistantLook.all) {
                  warmAssistant(other, robot, ratio);
                }
                return Center(
                  child: ExcludeSemantics(
                    child: AnimatedSwitcher(
                      duration: _still ? Duration.zero : Motion.fade,
                      child: RobotStage(key: ValueKey(look.kind), look: look, robotSize: robot, mood: AssistantMood.happy),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: Space.s),
          MergeSemantics(
            child: Column(
              children: [
                Text(look.name, style: PrepType.titleL, textAlign: TextAlign.center),
                Text(look.colour, style: PrepType.meta, textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The conversation: the robot big on its lit floor while the talk is short, giving way as it
  /// grows or when the keyboard opens; bubbles under it; the answer dock at the bottom.
  Widget _chatView(AssistantLook look) {
    return LayoutBuilder(
      builder: (context, box) {
        // The body's own MediaQuery has the keyboard removed (the Scaffold already made room), so
        // ask the screen's.
        final keyboard = MediaQuery.viewInsetsOf(this.context).bottom > 0;
        final h = box.maxHeight;
        final n = _lines.length;
        var size = keyboard ? h * 0.2 : (n <= 2 ? h * 0.46 : (n <= 4 ? h * 0.34 : h * 0.24));
        size = math.min(size, box.maxWidth * 0.9);
        // Too little room for a robot that reads as one: the words get the space.
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
                  child: s < 1 ? null : Center(child: RobotStage(look: look, robotSize: s, mood: _mood, level: _level)),
                );
              },
            ),
            Expanded(
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
                    sliver: SliverList.list(children: [for (final line in _lines) _Bubble(line: line, name: look.name)]),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.l),
                        child: _composer(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Text mode: the person chose to type, or their spoken answer is back as text to check and send.
  bool get _textMode => _prefersTyping || (!_recording && _field.text.trim().isNotEmpty);

  Widget _composer() {
    switch (_step) {
      case _Step.done:
        return PrimaryButton("Let's go", key: const ValueKey('onboarding-done'), onPressed: _finish);
      case _Step.pick:
        return const SizedBox.shrink();
      case _Step.name:
      case _Step.job:
      case _Step.about:
        final hint = switch (_step) {
          _Step.name => 'Your name',
          _Step.job => 'For example, barista',
          _ => 'School, work, strengths',
        };
        final skip = _step == _Step.about && !_recording && !_transcribing
            ? QuietButton('Not now', key: const ValueKey('onboarding-skip-about'), onPressed: _skipAbout)
            : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.m),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_note!, textAlign: TextAlign.center, style: PrepType.meta.copyWith(color: PrepColors.warning)),
                ),
              ),
            if (_textMode) ...[
              if (skip != null) Align(alignment: Alignment.centerRight, child: skip),
              _Composer(
                controller: _field,
                hint: _transcribing ? 'Writing it down' : hint,
                lines: switch (_step) {
                  _Step.name => 1,
                  _Step.job => 3,
                  _ => 5,
                },
                recording: _recording,
                busy: _transcribing,
                onMic: _toggleMic,
                onSend: _send,
                onChanged: () => setState(() {}),
              ),
            ] else
              _VoiceBar(
                recording: _recording,
                busy: _transcribing,
                heard: _field.text,
                onMic: _toggleMic,
                onType: () => setState(() {
                  _prefersTyping = true;
                  _note = null;
                }),
                trailing: skip,
              ),
          ],
        );
    }
  }
}

/// Voice first: one big accent mic to answer out loud, with typing as the quieter way in.
class _VoiceBar extends StatelessWidget {
  const _VoiceBar({
    required this.recording,
    required this.busy,
    required this.heard,
    required this.onMic,
    required this.onType,
    this.trailing,
  });

  final bool recording;
  final bool busy;
  final String heard;
  final VoidCallback onMic;
  final VoidCallback onType;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final caption = busy
        ? 'Writing it down'
        : recording
        ? (heard.trim().isEmpty ? 'Listening. Tap to stop.' : heard.trim())
        : 'Tap to answer';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            caption,
            style: PrepType.bodyL.copyWith(color: recording ? PrepColors.text : PrepColors.text2),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: Space.m),
        Builder(
          // The dock spans the screen between the gutters (no LayoutBuilder: the sliver around it asks
          // for its intrinsic height).
          builder: (context) {
            final width = MediaQuery.sizeOf(context).width - Space.gutter * 2;
            const disc = 80.0;
            final type = QuietButton(
              'Type instead',
              key: const ValueKey('onboarding-type'),
              icon: PrepIcons.keyboard,
              onPressed: busy || recording ? null : onType,
            );
            final mic = MetalDisc(
              recording ? PrepIcons.stop : PrepIcons.mic,
              key: const ValueKey('onboarding-mic'),
              label: recording ? 'Stop recording' : 'Answer by voice',
              size: disc,
              filled: !busy && !recording,
              fill: recording ? PrepColors.recording : null,
              onPressed: busy ? null : onMic,
            );
            final side = (width - disc) / 2 - Space.s;
            // Large text or a narrow phone: the mic alone on its line, the quiet actions under it.
            if (!_fitsBeside(context, 'Type instead', side) || (trailing != null && !_fitsBeside(context, 'Not now', side, icon: false))) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  mic,
                  const SizedBox(height: Space.s),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: Space.s,
                    runSpacing: Space.xs,
                    children: [type, ?trailing],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: Align(alignment: Alignment.centerLeft, child: type)),
                const SizedBox(width: Space.s),
                mic,
                const SizedBox(width: Space.s),
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: trailing ?? const SizedBox.shrink()),
                ),
              ],
            );
          },
        ),
      ],
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

/// The step track and a way out.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.steps, required this.done, required this.onSkip});

  final int steps;
  final int done;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final step = math.min(done + 1, steps);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.s, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: ProgressTrack(value: step / steps, label: 'Step $step of $steps', segments: steps),
          ),
          const SizedBox(width: Space.s),
          QuietButton('Skip', onPressed: onSkip),
        ],
      ),
    );
  }
}

/// One line of the conversation: the coach on metal at the left, you in the accent at the right.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.line, required this.name});

  final _Line line;
  final String name;

  @override
  Widget build(BuildContext context) {
    final mine = line.mine;
    final text = Text(line.text, style: PrepType.bodyL.copyWith(color: mine ? PrepColors.onAccent : PrepColors.text));
    const padding = EdgeInsets.symmetric(horizontal: 18, vertical: Space.m);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: Semantics(
            label: mine ? 'You: ${line.text}' : '$name: ${line.text}',
            excludeSemantics: true,
            child: mine
                ? DecoratedBox(
                    decoration: BoxDecoration(color: PrepColors.accent, borderRadius: BorderRadius.circular(Radii.card)),
                    child: Padding(padding: padding, child: text),
                  )
                : MetalCard(padding: padding, child: text),
          ),
        ),
      ),
    );
  }
}

/// The typing dock: a metal field, the mic to talk instead, and send. Spoken words land in the
/// field to check before sending.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.hint,
    required this.lines,
    required this.recording,
    required this.busy,
    required this.onMic,
    required this.onSend,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final int lines;
  final bool recording;
  final bool busy;
  final VoidCallback onMic;
  final VoidCallback onSend;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty && !recording && !busy;
    return MetalCard(
      radius: Radii.sheet,
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.xs, Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: TextField(
                key: const ValueKey('onboarding-field'),
                controller: controller,
                readOnly: recording || busy,
                minLines: 1,
                maxLines: lines,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: lines > 3 ? TextInputAction.newline : TextInputAction.send,
                onSubmitted: lines > 3 ? null : (_) => onSend(),
                onChanged: (_) => onChanged(),
                style: PrepType.bodyL,
                cursorColor: PrepColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: hint,
                  hintStyle: PrepType.bodyL.copyWith(color: PrepColors.text3),
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          MetalDisc(
            recording ? PrepIcons.stop : PrepIcons.mic,
            key: const ValueKey('onboarding-mic'),
            label: recording ? 'Stop recording' : 'Answer by voice',
            size: 48,
            fill: recording ? PrepColors.recording : null,
            onPressed: busy ? null : onMic,
          ),
          const SizedBox(width: Space.s),
          MetalDisc(
            PrepIcons.arrowUpRight,
            key: const ValueKey('onboarding-send'),
            label: 'Send',
            size: 48,
            filled: canSend,
            onPressed: canSend ? onSend : null,
          ),
        ],
      ),
    );
  }
}
