import 'package:flutter/material.dart';

import 'components.dart';
import 'icons.dart';
import 'tokens.dart';

/// Shared chrome for anything that runs as a sequence of steps (a practice session, a drill
/// lesson): a top bar with a close control and a progress track, and a bottom bar that keeps the
/// screen's one next action in reach. The page between them scrolls.

/// How far through a sequence the person is: a single rounded track filled in the coach colour.
/// [value] is 0..1. Screen readers hear [label] ("Question 2 of 3").
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({super.key, required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: label,
      value: '${(value.clamp(0.0, 1.0) * 100).round()} percent',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 8,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: PrepColors.surface2),
              TweenAnimationBuilder<double>(
                tween: Tween(end: value.clamp(0.0, 1.0)),
                duration: reduce ? Duration.zero : Motion.enter,
                curve: Motion.standard,
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: PrepColors.accent, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top of a step sequence: close on the left, the progress track filling the rest, and an
/// optional short [caption] under it ("Question 2 of 3 · Barista").
class StepTopBar extends StatelessWidget {
  const StepTopBar({
    super.key,
    required this.progress,
    required this.progressLabel,
    required this.onClose,
    this.caption,
    this.closeLabel = 'Close',
  });

  final double progress;
  final String progressLabel;
  final VoidCallback onClose;
  final String? caption;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.gutter, Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconAction(PrepIcons.close, label: closeLabel, onPressed: onClose, plain: true),
              const SizedBox(width: Space.s),
              Expanded(child: ProgressTrack(value: progress, label: progressLabel)),
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
