import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/hologram.dart';
import '../../design/tokens.dart';

/// Shared frame for the coach screens: top bar, the presence (smaller when the keyboard is up),
/// then [body] scrolling beneath it.
class CoachScaffold extends StatelessWidget {
  const CoachScaffold({
    super.key,
    required this.onClose,
    required this.body,
    this.status,
    this.presenceSize = 160,
    this.level,
  });

  final VoidCallback onClose;
  final Widget body;
  final String? status;
  final double presenceSize;
  final ValueListenable<double>? level;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final target = keyboard ? presenceSize * 0.55 : presenceSize;
    const barHeight = 64.0;
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        // The presence grows while the interviewer talks and steps back for typing and reading.
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: Motion.enter,
          curve: Motion.standard,
          builder: (context, size, _) => PresenceBackdrop(
            top: barHeight,
            size: size,
            level: level,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CoachTopBar(onClose: onClose, status: status),
                SizedBox(height: size),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reveals a sentence word by word while the interviewer says it. The full text is laid out from
/// the start (unrevealed words are transparent), so nothing reflows as words appear.
class RevealController extends ValueNotifier<int> {
  RevealController() : super(0);

  String _text = '';
  List<String> _words = const [];
  Timer? _timer;

  String get text => _text;
  List<String> get words => _words;
  bool get complete => value >= _words.length;

  /// Starts revealing [text] at roughly a natural speaking pace. [showAll] snaps to the end
  /// when the voice finishes early (or is interrupted).
  void start(String text, {Duration perWord = const Duration(milliseconds: 330)}) {
    _timer?.cancel();
    _text = text;
    _words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    value = _words.isEmpty ? 0 : 1;
    _timer = Timer.periodic(perWord, (timer) {
      if (value >= _words.length) {
        timer.cancel();
      } else {
        value = value + 1;
      }
    });
  }

  void showAll() {
    _timer?.cancel();
    value = _words.length;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class RevealText extends StatelessWidget {
  const RevealText({super.key, required this.controller, required this.style});

  final RevealController controller;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: controller,
      builder: (context, shown, _) {
        final words = controller.words;
        final seen = words.take(shown).join(' ');
        final rest = words.skip(shown).join(' ');
        return Semantics(
          label: controller.text,
          header: true,
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(text: seen),
                if (rest.isNotEmpty) TextSpan(text: '${seen.isEmpty ? '' : ' '}$rest', style: style.copyWith(color: const Color(0x00000000))),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The record control: a ring of sixty hairline ticks around a round button. The ring shows
/// time: it fills up during an answer, or counts down during the short job recording.
class RecordButton extends StatelessWidget {
  const RecordButton({
    super.key,
    required this.recording,
    required this.progress,
    required this.onPressed,
    this.countdown = false,
  });

  final bool recording;
  final ValueListenable<double> progress;
  final VoidCallback? onPressed;
  final bool countdown;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: recording ? 'Stop recording' : 'Start recording',
      // excludeSemantics hides the InkWell's own tap, so screen readers need it here.
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 116,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (context, p, _) => CustomPaint(
                  painter: _TickRing(progress: p, countdown: countdown, active: recording),
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              shape: CircleBorder(side: BorderSide(color: PrepColors.text.withValues(alpha: enabled ? 0.85 : 0.25), width: 1.5)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('record-button'),
                onTap: onPressed,
                child: SizedBox.square(
                  dimension: 76,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Motion.decelerate,
                      width: recording ? 26 : 30,
                      height: recording ? 26 : 30,
                      decoration: BoxDecoration(
                        color: PrepColors.recording.withValues(alpha: enabled ? 1 : 0.35),
                        borderRadius: BorderRadius.circular(recording ? 6 : 15),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TickRing extends CustomPainter {
  _TickRing({required this.progress, required this.countdown, required this.active});

  final double progress;
  final bool countdown;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    const ticks = 60;
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final p = progress.clamp(0.0, 1.0);
    final lit = countdown ? ((1 - p) * ticks).ceil() : (p * ticks).floor();
    for (var i = 0; i < ticks; i++) {
      final a = (i * 6 - 90) * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      final len = i % 5 == 0 ? 8.0 : 3.5;
      final on = active && i < lit;
      canvas.drawLine(
        center + dir * (r - len),
        center + dir * r,
        Paint()
          ..color = on ? PrepColors.accent : PrepColors.lineStrong.withValues(alpha: active ? 1 : 0.8)
          ..strokeWidth = on ? 1.5 : 1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_TickRing old) => old.progress != progress || old.countdown != countdown || old.active != active;
}

/// An honest progress line: says what is happening, with a thin indeterminate bar.
class LoadingLine extends StatelessWidget {
  const LoadingLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: PrepType.bodyLMedium),
          const SizedBox(height: Space.m),
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            child: LinearProgressIndicator(minHeight: 2, color: PrepColors.accent, backgroundColor: PrepColors.line),
          ),
        ],
      ),
    );
  }
}

/// A problem, said plainly, with what to do about it.
class ProblemNote extends StatelessWidget {
  const ProblemNote({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: PrepType.titleM),
          const SizedBox(height: Space.xs),
          Text(body, style: PrepType.body),
        ],
      ),
    );
  }
}

String clock(int ms) {
  final total = (ms / 1000).floor().clamp(0, 5999);
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
