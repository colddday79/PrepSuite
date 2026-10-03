import 'package:flutter/material.dart';

import 'components.dart';
import 'icons.dart';
import 'metal.dart';
import 'tokens.dart';

/// Shared chrome for anything that runs as a sequence of steps (a practice session, a drill
/// lesson): a top bar with a close control and a thin progress track, and a bottom bar that keeps
/// the screen's one next action in reach. The page between them scrolls.

/// How far through a sequence the person is: a thin track on the canvas, filled in the accent.
/// [segments] splits it into that many steps (the questions of a practice), each filling in turn.
/// [value] is 0..1. Screen readers hear [label] ("Question 2 of 3").
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({super.key, required this.value, required this.label, this.segments = 1});

  final double value;
  final String label;
  final int segments;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: label,
      value: '${(value.clamp(0.0, 1.0) * 100).round()} percent',
      excludeSemantics: true,
      child: SizedBox(
        height: 4,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0.0, 1.0)),
          duration: reduce ? Duration.zero : Motion.enter,
          curve: Motion.standard,
          builder: (context, v, _) => CustomPaint(
            painter: _TrackPainter(
              value: v,
              segments: segments < 1 ? 1 : segments,
              track: PrepColors.lineStrong,
              fill: PrepColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.value, required this.segments, required this.track, required this.fill});

  final double value;
  final int segments;
  final Color track;
  final Color fill;

  static const double _gap = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final radius = Radius.circular(h / 2);
    final width = (size.width - _gap * (segments - 1)) / segments;
    final trackPaint = Paint()..color = track;
    final fillPaint = Paint()..color = fill;
    for (var i = 0; i < segments; i++) {
      final left = i * (width + _gap);
      canvas.drawRRect(RRect.fromLTRBR(left, 0, left + width, h, radius), trackPaint);
      final part = (value * segments - i).clamp(0.0, 1.0);
      if (part <= 0) continue;
      // Never thinner than the track is tall, so a started step reads as a dot, not a sliver.
      final filled = (width * part).clamp(h, width);
      canvas.drawRRect(RRect.fromLTRBR(left, 0, left + filled, h, radius), fillPaint);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.value != value || old.segments != segments || old.track != track || old.fill != fill;
}

/// The top of a step sequence: close on the left, the progress track filling the rest, an
/// optional short [count] at the end ("1/3"), and an optional [caption] under it.
///
/// [metalClose] draws the close control as a [MetalDisc] (the practice session); without it the
/// close stays the plain [IconAction] the drill lessons use.
class StepTopBar extends StatelessWidget {
  const StepTopBar({
    super.key,
    required this.progress,
    required this.progressLabel,
    required this.onClose,
    this.caption,
    this.closeLabel = 'Close',
    this.segments = 1,
    this.count,
    this.metalClose = false,
  });

  final double progress;
  final String progressLabel;
  final VoidCallback onClose;
  final String? caption;
  final String closeLabel;

  /// How many steps the track shows (the questions of a practice).
  final int segments;

  /// Where the person is, as numbers ("1/3"). The track already tells screen readers.
  final String? count;
  final bool metalClose;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    return Padding(
      padding: EdgeInsets.fromLTRB(metalClose ? Space.l : Space.s, Space.s, Space.gutter, Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (metalClose)
                MetalDisc(PrepIcons.close, label: closeLabel, onPressed: onClose, size: 48)
              else
                IconAction(PrepIcons.close, label: closeLabel, onPressed: onClose, plain: true),
              SizedBox(width: metalClose ? Space.l : Space.s),
              Expanded(child: ProgressTrack(value: progress, label: progressLabel, segments: segments)),
              if (count != null) ...[
                const SizedBox(width: Space.l),
                ExcludeSemantics(
                  child: Text(
                    count,
                    style: PrepType.label.copyWith(
                      color: PrepColors.text2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(left: Space.m, top: Space.xs),
              child: Text(caption!, style: PrepType.meta, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

/// The bottom of a step screen: a hairline, then the primary action (and optional quiet actions)
/// above the system gesture area. Put it in `Scaffold.bottomNavigationBar` or the last slot of a
/// Column so it never scrolls away.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.children, this.color});

  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? PrepColors.bg,
        border: Border(top: BorderSide(color: PrepColors.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: Space.m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
