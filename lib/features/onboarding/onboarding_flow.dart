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
import '../../design/hologram.dart';
import '../../design/icons.dart';
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
        await _say('Great. Now tell me a bit about you: studies, work, strengths.');
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
    setState(() => _lines.add(const _Line('Skip for now', mine: true)));
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
            ? 'The microphone is off, so type your answer.'
            : 'Allow the microphone, or type your answer.';
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
        _note = "The microphone didn't start, so type your answer.";
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
        _note = "I couldn't hear that. Try again, or type your answer.";
      } else {
        _field.text = heard;
        _field.selection = TextSelection.collapsed(offset: heard.length);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AssistantLook>(
      valueListenable: _services.assistant,
      builder: (context, look, _) => Scaffold(
        backgroundColor: PrepColors.bg,
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
    );
  }

  Widget _pickView(AssistantLook look) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(0.0, box.maxWidth - Space.gutter * 2);
        final header = [
          Text('Choose your coach', style: PrepType.display),
          const SizedBox(height: Space.xs),
          Text('Same voice, different look. Change it any time.', style: PrepType.body),
        ];
        Widget coach(double size) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AssistantAvatar(look: look, size: size, mood: AssistantMood.happy),
                Text(look.name, style: PrepType.titleL, textAlign: TextAlign.center),
                Text(look.colour, style: PrepType.caption, textAlign: TextAlign.center),
              ],
            );
        final footer = [
          AssistantPicker(selected: look.kind, onSelected: _services.assistant.choose),
          const SizedBox(height: Space.xl),
          PrimaryButton('Continue', key: const ValueKey('onboarding-continue'), onPressed: _begin),
        ];
        const padding = EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.xxl);

        // When everything fits, the coach fills the middle and the picker and Continue sit at the
        // bottom, with no empty band under the button. Small screens and large text scroll instead.
        final room = box.maxHeight - _pickChromeHeight(context, width);
        if (room >= 140) {
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...header,
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, area) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      final size = math.min(area.maxWidth, area.maxHeight - Space.l * 2 - 48 * scale).clamp(72.0, 420.0);
                      return Center(child: coach(size));
                    },
                  ),
                ),
                ...footer,
              ],
            ),
          );
        }
        final size = math.min(width, box.maxHeight * 0.48).clamp(72.0, 420.0);
        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...header,
              const SizedBox(height: Space.l),
              Center(child: coach(size)),
              const SizedBox(height: Space.l),
              ...footer,
            ],
          ),
        );
      },
    );
  }

  /// Roughly how tall the picker screen is without the coach: titles, the picker rows, Continue and
  /// the padding, at the current text size. Used only to choose between the fixed and scrolling layouts.
  double _pickChromeHeight(BuildContext context, double width) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final count = AssistantLook.all.length;
    final columns = ((width + Space.s) / (56 * scale + Space.s)).floor().clamp(1, count);
    final rows = (count / columns).ceil();
    final tile = (width - Space.s * (columns - 1)) / columns;
    final picker = rows * (tile + 16 * scale + Space.s * 2 + Space.xs) + (rows - 1) * Space.s;
    final titleLines = width < 340 * scale ? 2 : 1;
    final bodyLines = width < 380 * scale ? 2 : 1;
    final text = 36 * scale * titleLines + Space.xs + 23 * scale * bodyLines;
    return Space.l + Space.xxl + text + picker + Space.xl + 56 * scale;
  }

  Widget _chatView(AssistantLook look) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom > 0;
    final h = media.size.height;
    // The coach is big while the conversation is short and gives way as it grows, so the screen is
    // never a small robot over a large empty gap.
    final n = _lines.length;
    final target = keyboard
        ? h * 0.13
        : n <= 2
        ? math.min(media.size.width * 0.7, h * 0.34)
        : (n <= 4 ? h * 0.25 : h * 0.19);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        // The whole conversation can scroll when the keyboard or larger text leaves less room.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: math.min(target, box.maxHeight * (keyboard ? 0.18 : 0.4))),
                duration: Motion.enter,
                curve: Motion.standard,
                builder: (context, size, _) => SizedBox(
                  height: size,
                  child: Center(
                    child: AssistantAvatar(look: look, size: size, mood: _mood, level: _level),
                  ),
                ),
              ),
              const SizedBox(height: Space.l),
              for (final line in _lines) _Bubble(line: line, name: look.name),
              Padding(
                padding: const EdgeInsets.only(top: Space.s, bottom: Space.l),
                child: _composer(),
              ),
            ],
          ),
        ),
      ),
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
          _Step.job => 'For example, junior data analyst',
          _ => 'Studies, work, strengths',
        };
        final skip = _step == _Step.about && !_recording && !_transcribing
            ? QuietButton('Skip for now', key: const ValueKey('onboarding-skip-about'), onPressed: _skipAbout)
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s, left: Space.xs),
                child: Text(_note!, style: PrepType.meta.copyWith(color: PrepColors.danger)),
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

/// Voice first: one big mic to answer out loud, with typing as the quieter alternative.
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
      children: [
        Text(
          caption,
          style: PrepType.bodyL.copyWith(color: recording ? PrepColors.text : PrepColors.text2),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.m),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: QuietButton(
                  'Type instead',
                  key: const ValueKey('onboarding-type'),
                  icon: PrepIcons.keyboard,
                  onPressed: busy || recording ? null : onType,
                ),
              ),
            ),
            _RoundButton(
              key: const ValueKey('onboarding-mic'),
              icon: recording ? PrepIcons.stop : PrepIcons.mic,
              label: recording ? 'Stop recording' : 'Answer by voice',
              fill: recording ? PrepColors.recording : PrepColors.ink,
              ink: PrepColors.bg,
              size: 76,
              iconSize: 32,
              onPressed: busy ? null : onMic,
            ),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: trailing ?? const SizedBox.shrink()),
            ),
          ],
        ),
      ],
    );
  }
}

/// A thin progress bar in the assistant's colour and a way out.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.steps, required this.done, required this.onSkip});

  final int steps;
  final int done;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.s, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: 'Step ${math.min(done + 1, steps)} of $steps',
              child: Row(
                children: [
                  for (var i = 0; i < steps; i++) ...[
                    if (i > 0) const SizedBox(width: Space.xs),
                    Expanded(
                      child: AnimatedContainer(
                        duration: Motion.enter,
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= done ? PrepColors.accent : PrepColors.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.s),
          QuietButton('Skip', onPressed: onSkip),
        ],
      ),
    );
  }
}

/// One line of the conversation: the coach on the left, you on the right.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.line, required this.name});

  final _Line line;
  final String name;

  @override
  Widget build(BuildContext context) {
    final mine = line.mine;
    const r = Radius.circular(20);
    const tip = Radius.circular(6);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: Semantics(
            label: mine ? 'You: ${line.text}' : '$name: ${line.text}',
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: mine ? PrepColors.accent : PrepColors.surface1,
                borderRadius: BorderRadius.only(
                  topLeft: mine ? r : tip,
                  topRight: mine ? tip : r,
                  bottomLeft: r,
                  bottomRight: r,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                child: Text(line.text, style: PrepType.bodyL.copyWith(color: mine ? PrepColors.bg : PrepColors.text)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The answer bar: type, or tap the mic and talk; the words land in the field to check, then send.
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
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.xs, Space.xs),
      decoration: BoxDecoration(
        color: PrepColors.surface1,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: recording ? PrepColors.recording : PrepColors.lineStrong),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
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
          _RoundButton(
            key: const ValueKey('onboarding-mic'),
            icon: recording ? PrepIcons.stop : PrepIcons.mic,
            label: recording ? 'Stop recording' : 'Answer by voice',
            fill: recording ? PrepColors.recording : PrepColors.surface2,
            ink: recording ? PrepColors.bg : PrepColors.text,
            size: 52,
            iconSize: 24,
            onPressed: busy ? null : onMic,
          ),
          const SizedBox(width: Space.xs),
          _RoundButton(
            key: const ValueKey('onboarding-send'),
            icon: PrepIcons.arrowUpRight,
            label: 'Send',
            fill: canSend ? PrepColors.accent : PrepColors.surface2,
            ink: canSend ? PrepColors.bg : PrepColors.text3,
            onPressed: canSend ? onSend : null,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.fill,
    required this.ink,
    required this.onPressed,
    this.size = 48,
    this.iconSize = 20,
  });

  final PrepIcons icon;
  final String label;
  final Color fill;
  final Color ink;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: PrepIcon(icon, color: ink, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
