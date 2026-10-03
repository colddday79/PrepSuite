import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';

/// The pieces a drill exercise is built from: answer boxes, word tiles, the gap in a sentence, the
/// numbered slots of an ordering exercise, and the small marks that say right or not quite.
///
/// Colour never carries meaning alone: a checked box always has an icon and a few words as well.

/// How a box looks. Before checking it is [idle] or [selected]; after, the right answer is
/// [correct], a wrong pick is [wrong], and the rest step back as [muted].
enum BoxTone { idle, selected, correct, wrong, muted }

@immutable
class _Paint {
  const _Paint(this.fill, this.edge, this.width, this.ink);

  final Color fill;
  final Color edge;
  final double width;
  final Color ink;
}

_Paint _paintFor(BoxTone tone) => switch (tone) {
  BoxTone.idle => _Paint(PrepColors.surface1, PrepColors.line, 1, PrepColors.text),
  BoxTone.selected => _Paint(PrepColors.accentTint, PrepColors.accent, 2, PrepColors.text),
  BoxTone.correct => _Paint(PrepColors.successTint, PrepColors.success, 2, PrepColors.text),
  BoxTone.wrong => _Paint(PrepColors.warningTint, PrepColors.warning, 2, PrepColors.text),
  BoxTone.muted => _Paint(PrepColors.surface1, PrepColors.line, 1, PrepColors.text2),
};

PrepIcons? _markFor(BoxTone tone) => switch (tone) {
  BoxTone.correct => PrepIcons.check,
  BoxTone.wrong => PrepIcons.close,
  _ => null,
};

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The fill and edge of a box, easing between tones. The edge is drawn inside the shape, so a
/// thicker selected edge never moves the text.
class _Surface extends StatelessWidget {
  const _Surface({required this.tone, required this.radius, required this.child});

  final BoxTone tone;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final paint = _paintFor(tone);
    return TweenAnimationBuilder<Decoration>(
      tween: DecorationTween(
        end: ShapeDecoration(
          color: paint.fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(color: paint.edge, width: paint.width),
          ),
        ),
      ),
      duration: _still(context) ? Duration.zero : Motion.fade,
      curve: Motion.standard,
      builder: (context, decoration, child) => DecoratedBox(decoration: decoration, child: child),
      child: child,
    );
  }
}

/// A small filled disc with a dark hairline icon: check for right, a cross for not quite.
class StatusMark extends StatelessWidget {
  const StatusMark(this.icon, {super.key, required this.color, this.size = 24});

  final PrepIcons icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: PrepIcon(icon, color: PrepColors.bg, size: size * 0.72)),
      ),
    );
  }
}

/// A full-width answer: a choice, a sentence, or one part of a story to order.
///
/// [note] is a couple of words under the text once checked ("Best answer", "Your pick"), so the
/// state is said in words as well as colour and icon. [leading] is a step number.
class AnswerBox extends StatelessWidget {
  const AnswerBox({
    super.key,
    required this.text,
    required this.tone,
    required this.onTap,
    required this.semanticLabel,
    this.note,
    this.leading,
  });

  final String text;
  final BoxTone tone;
  final VoidCallback? onTap;
  final String semanticLabel;
  final String? note;
  final String? leading;

  static const _shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control)));

  @override
  Widget build(BuildContext context) {
    final paint = _paintFor(tone);
    final mark = _markFor(tone);
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: tone == BoxTone.selected,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: FocusRing(
        child: _Surface(
          tone: tone,
          radius: Radii.control,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              customBorder: _shape,
              focusColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56, minWidth: double.infinity),
                child: Padding(
                  padding: const EdgeInsets.all(Space.l),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (leading != null) ...[
                        SizedBox(
                          width: Space.l,
                          child: Text(leading!, style: PrepType.bodyLMedium.copyWith(color: PrepColors.text3)),
                        ),
                        const SizedBox(width: Space.m),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(text, style: PrepType.bodyL.copyWith(color: paint.ink)),
                            if (note != null) ...[
                              const SizedBox(height: Space.xs),
                              Text(note!, style: PrepType.label.copyWith(color: paint.edge)),
                            ],
                          ],
                        ),
                      ),
                      if (mark != null) ...[
                        const SizedBox(width: Space.m),
                        StatusMark(mark, color: paint.edge),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A word or short phrase in the bank. Once placed in the sentence, [ghost] keeps its outline so
/// the bank doesn't shift.
class WordTile extends StatelessWidget {
  const WordTile({
    super.key,
    required this.text,
    required this.tone,
    required this.onTap,
    required this.semanticLabel,
    this.ghost = false,
  });

  final String text;
  final BoxTone tone;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool ghost;

  static const double _radius = 24;
  static const _shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(_radius)));
  static const _padding = EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m);

  @override
  Widget build(BuildContext context) {
    if (ghost) {
      return ExcludeSemantics(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(_radius)),
              side: BorderSide(color: PrepColors.line),
            ),
          ),
          child: Padding(
            padding: _padding,
            child: Text(text, style: PrepType.bodyL.copyWith(color: Colors.transparent)),
          ),
        ),
      );
    }
    final paint = _paintFor(tone);
    final mark = _markFor(tone);
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: tone == BoxTone.selected,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: FocusRing(
        radius: _radius,
        child: _Surface(
          tone: tone,
          radius: _radius,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              customBorder: _shape,
              focusColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Padding(
                  padding: _padding,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(text, style: PrepType.bodyL.copyWith(color: paint.ink))),
                      if (mark != null) ...[
                        const SizedBox(width: Space.s),
                        StatusMark(mark, color: paint.edge, size: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gap in a fill-in sentence: an empty slot, or the chosen word (tap it to take it back).
class BlankGap extends StatelessWidget {
  const BlankGap({super.key, required this.word, required this.tone, required this.onTap});

  final String? word;
  final BoxTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final word = this.word;
    if (word == null) {
      return Semantics(
        label: 'Blank',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Space.xxs, vertical: Space.xs),
          child: SizedBox(
            width: 88,
            height: 40,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: PrepColors.surface2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.chip))),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xxs, vertical: Space.xxs),
      child: WordTile(
        text: word,
        tone: tone,
        onTap: onTap,
        semanticLabel: onTap == null ? word : '$word, in the blank. Tap to take it out',
      ),
    );
  }
}

/// One numbered step in an ordering exercise: empty until a part is placed in it.
class OrderSlot extends StatelessWidget {
  const OrderSlot({
    super.key,
    required this.number,
    required this.text,
    required this.tone,
    required this.onTap,
    this.note,
  });

  final int number;
  final String? text;
  final BoxTone tone;
  final VoidCallback? onTap;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    if (text == null) {
      return Semantics(
        label: 'Step $number, empty',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56, minWidth: double.infinity),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(Radii.control)),
                side: BorderSide(color: PrepColors.lineStrong),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$number', style: PrepType.bodyLMedium.copyWith(color: PrepColors.text3)),
              ),
            ),
          ),
        ),
      );
    }
    final state = switch (tone) {
      BoxTone.correct => ', in the right place',
      BoxTone.wrong => ', not quite. ${note ?? ''}',
      _ => onTap == null ? '' : '. Tap to take it out',
    };
    return AnswerBox(
      text: text,
      tone: tone,
      onTap: onTap,
      leading: '$number',
      note: note,
      semanticLabel: 'Step $number: $text$state',
    );
  }
}

/// A quoted line with a small label above it: what the interviewer asks, the line to rewrite, or
/// one way to say it. A hairline rule on the left marks it as a quote.
class QuoteBlock extends StatelessWidget {
  const QuoteBlock({super.key, required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label: $text',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: PrepColors.lineStrong, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: Space.l, top: Space.xxs, bottom: Space.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: PrepType.meta),
              const SizedBox(height: Space.xs),
              Text(text, style: PrepType.bodyLMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 4 dp progress line for the skill path. Decorative: the words beside it say the same.
class ThinTrack extends StatelessWidget {
  const ThinTrack({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: PrepColors.surface2),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: ColoredBox(color: PrepColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eases a new exercise in: a short fade and a small slide from the right. Nothing moves when
/// the system asks for less motion.
class EnterFade extends StatelessWidget {
  const EnterFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (_still(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.enter,
      curve: Motion.decelerate,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(Space.l * (1 - t), 0), child: child),
      ),
    );
  }
}
