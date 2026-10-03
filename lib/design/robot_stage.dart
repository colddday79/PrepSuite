import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant.dart';
import 'assistant_avatar.dart';
import 'tokens.dart';

/// The robot shown as a lit product on its own stage, the way the owner's references show a lamp
/// or a drone: a dial of hairline ticks around it (one accent arc when there is real [progress] to
/// show), a satin metal pedestal under its feet with the accent light pooled on it, and its contact
/// shadow. Use it wherever the robot is large: Home, onboarding, the session.
///
/// [robotSize] is the side of the robot's render square; the stage is the same square.
class RobotStage extends StatelessWidget {
  const RobotStage({
    super.key,
    required this.look,
    required this.robotSize,
    this.mood = AssistantMood.idle,
    this.level,
    this.progress,
    this.dial = true,
    this.pedestal = true,
    this.animate = true,
    this.semanticLabel,
  });

  final AssistantLook look;
  final double robotSize;
  final AssistantMood mood;
  final ValueListenable<double>? level;

  /// 0..1 for a real measure (drills done, time used). Null draws the dial without an arc.
  final double? progress;
  final bool dial;
  final bool pedestal;
  final bool animate;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final stage = TweenAnimationBuilder<double>(
      tween: Tween(end: (progress ?? 0).clamp(0.0, 1.0)),
      duration: reduce ? Duration.zero : Motion.enter,
      curve: Motion.standard,
      builder: (context, value, child) => CustomPaint(
        painter: _StagePainter(
          progress: progress == null ? null : value,
          dial: dial,
          pedestal: pedestal,
          tick: PrepColors.line,
          tickStrong: PrepColors.lineStrong,
          accent: PrepColors.accent,
          top: PrepColors.surface2,
          bottom: PrepColors.metalBottom,
          rim: PrepColors.rimLight,
        ),
        child: child,
      ),
      child: AssistantAvatar(
        look: look,
        size: robotSize,
        mood: mood,
        level: level,
        animate: animate,
        semanticLabel: semanticLabel,
      ),
    );
    return SizedBox.square(dimension: robotSize, child: stage);
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter({
    required this.progress,
    required this.dial,
    required this.pedestal,
    required this.tick,
    required this.tickStrong,
    required this.accent,
    required this.top,
    required this.bottom,
    required this.rim,
  });

  final double? progress;
  final bool dial;
  final bool pedestal;
  final Color tick;
  final Color tickStrong;
  final Color accent;
  final Color top;
  final Color bottom;
  final Color rim;

  // Matched to the Blender camera: the robot's floor line and the middle of its body.
  static const _floorY = 0.925;
  static const _centreY = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (dial) _paintDial(canvas, s);
    if (pedestal) _paintPedestal(canvas, s);
  }

  void _paintDial(Canvas canvas, double s) {
    final c = Offset(s * 0.5, s * _centreY);
    final outer = s * 0.5;
    // A watch bezel: 72 hairline ticks, a longer one every 30 degrees.
    for (var i = 0; i < 72; i++) {
      final a = i / 72 * 2 * math.pi - math.pi / 2;
      final major = i % 6 == 0;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + dir * (outer - s * (major ? 0.04 : 0.022)),
        c + dir * (outer - s * 0.006),
        Paint()
          ..color = major ? tickStrong : tick
          ..strokeWidth = math.max(1, s * (major ? 0.004 : 0.0028))
          ..strokeCap = StrokeCap.round,
      );
    }
    // One inner hairline ring, then the accent arc for real progress (270 degrees, open at the floor).
    final r = outer - s * 0.065;
    final rect = Rect.fromCircle(center: c, radius: r);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1, s * 0.0028)
      ..color = tick;
    canvas.drawArc(rect, start, sweep, false, line);
    final p = progress;
    if (p != null && p > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep * p,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(2.5, s * 0.011)
          ..color = accent,
      );
      // A small bright bead where the arc ends: the "you are here" of the dial.
      final end = start + sweep * p;
      canvas.drawCircle(
        c + Offset(math.cos(end), math.sin(end)) * r,
        math.max(3, s * 0.016),
        Paint()..color = accent,
      );
    }
  }

  void _paintPedestal(Canvas canvas, double s) {
    final centre = Offset(s * 0.5, s * (_floorY + 0.012));
    final w = s * 0.6;
    final h = s * 0.1;
    final depth = s * 0.03;
    final topRect = Rect.fromCenter(center: centre, width: w, height: h);
    final sideRect = topRect.shift(Offset(0, depth));
    // The disc's edge, then its top face lit from above, then a light rim along the far edge.
    canvas.drawOval(sideRect, Paint()..color = bottom);
    canvas.drawRect(
      Rect.fromLTRB(topRect.left, topRect.center.dy, topRect.right, sideRect.center.dy),
      Paint()..color = bottom,
    );
    canvas.drawOval(
      topRect,
      Paint()..shader = ui.Gradient.linear(topRect.topCenter, topRect.bottomCenter, [top, bottom]),
    );
    canvas.drawOval(
      topRect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(topRect.topCenter, topRect.bottomCenter, [rim, rim.withValues(alpha: 0)]),
    );
    // The accent light catching the front edge of the disc.
    canvas.drawArc(
      sideRect.deflate(0.5),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, s * 0.004)
        ..shader = ui.Gradient.linear(sideRect.centerLeft, sideRect.centerRight, [
          accent.withValues(alpha: 0),
          accent.withValues(alpha: 0.55),
          accent.withValues(alpha: 0),
        ], const [0, 0.5, 1]),
    );
  }

  @override
  bool shouldRepaint(_StagePainter old) =>
      old.progress != progress ||
      old.dial != dial ||
      old.pedestal != pedestal ||
      old.accent != accent ||
      old.tick != tick ||
      old.top != top;
}
