import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/glass.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';

/// The pieces a drill exercise is built from: metal answer tiles, word tiles, the gap in a
/// sentence, the numbered slots of an ordering exercise, and the small marks that say right or not
/// quite.
///
/// Colour never carries meaning alone: a checked tile always has an icon and a few words as well.

/// How a tile looks. Before checking it is [idle] or [selected]; after, the right answer is
/// [correct], a wrong pick is [wrong], and the rest step back as [muted].
enum BoxTone { idle, selected, correct, wrong, muted }

/// The paint of one tone: the metal gradient, a status wash laid over it, an inner ring and the
/// text colour.
@immutable
class _TileLook {
  const _TileLook({required this.top, required this.bottom, required this.wash, required this.ring, required this.ink});

  final Color top;
  final Color bottom;
  final Color wash;
  final Color ring;
  final Color ink;

  static _TileLook lerp(_TileLook a, _TileLook b, double t) => _TileLook(
    top: Color.lerp(a.top, b.top, t)!,
    bottom: Color.lerp(a.bottom, b.bottom, t)!,
    wash: Color.lerp(a.wash, b.wash, t)!,
    ring: Color.lerp(a.ring, b.ring, t)!,
    ink: Color.lerp(a.ink, b.ink, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is _TileLook &&
      other.top == top &&
      other.bottom == bottom &&
      other.wash == wash &&
      other.ring == ring &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(top, bottom, wash, ring, ink);
}

class _LookTween extends Tween<_TileLook> {
  _LookTween({super.end});

  @override
  _TileLook lerp(double t) => _TileLook.lerp(begin!, end!, t);
}

const _clear = Color(0x00000000);

/// The status colour of a checked tone, or null before checking.
Color? _statusOf(BoxTone tone) => switch (tone) {
  BoxTone.correct => PrepColors.success,
  BoxTone.wrong => PrepColors.warning,
  _ => null,
};

_TileLook _lookFor(BoxTone tone) {
  final status = _statusOf(tone);
  if (tone == BoxTone.selected) {
    // Picked: the raised metal of a disc, with a thin accent ring.
    return _TileLook(
      top: PrepColors.surface2,
      bottom: Color.lerp(PrepColors.surface2, PrepColors.metalBottom, 0.4)!,
      wash: _clear,
      ring: PrepColors.accentDeep,
      ink: PrepColors.text,
    );
  }
  return _TileLook(
    top: PrepColors.metalTop,
    bottom: PrepColors.metalBottom,
    wash: status == null ? _clear : status.withValues(alpha: 0.14),
    ring: status == null ? _clear : status.withValues(alpha: 0.4),
    ink: tone == BoxTone.muted ? PrepColors.text2 : PrepColors.text,
  );
}

PrepIcons? _markFor(BoxTone tone) => switch (tone) {
  BoxTone.correct => PrepIcons.check,
  BoxTone.wrong => PrepIcons.close,
  _ => null,
};

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Satin metal under a tile, easing between tones. The ring is drawn inside the shape, so a picked
/// tile never moves its text.
class _Tile extends StatelessWidget {
  const _Tile({required this.tone, required this.radius, required this.child});

  final BoxTone tone;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<_TileLook>(
      tween: _LookTween(end: _lookFor(tone)),
      duration: _still(context) ? Duration.zero : Motion.fade,
      curve: Motion.standard,
      builder: (context, look, child) => CustomPaint(painter: _TilePainter(look, radius), child: child),
      child: child,
    );
  }
}

class _TilePainter extends CustomPainter {
  _TilePainter(this.look, this.radius);

  final _TileLook look;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    // Smoked glass like every card (lib/design/glass.dart), then the status wash and the ring.
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    paintGlass(canvas, rrect, top: look.top, bottom: look.bottom);
    if (look.wash.a > 0) canvas.drawRRect(rrect, Paint()..color = look.wash);
    if (look.ring.a > 0) {
      canvas.drawRRect(
        rrect.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = look.ring,
      );
    }
  }

  @override
  bool shouldRepaint(_TilePainter old) => old.look != look || old.radius != radius;
}

/// A small filled disc with a dark hairline icon: check for right, a cross for not quite.
class StatusMark extends StatelessWidget {
  const StatusMark(this.icon, {super.key, required this.color, this.size = 24, this.ink});

  final PrepIcons icon;
  final Color color;
  final double size;

  /// The icon colour; the canvas by default (dark on a bright status colour).
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: PrepIcon(icon, color: ink ?? PrepColors.bg, size: size * 0.7)),
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

  static const double _radius = Radii.card;
  static const _shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(_radius)));

  @override
  Widget build(BuildContext context) {
    final mark = _markFor(tone);
    final status = _statusOf(tone);
    final ink = tone == BoxTone.muted ? PrepColors.text2 : PrepColors.text;
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
        child: _Tile(
          tone: tone,
          radius: _radius,
          child: Material(
            type: MaterialType.transparency,
            shape: _shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              focusColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60, minWidth: double.infinity),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (leading != null) ...[
                        SizedBox(
                          width: Space.xl,
                          child: Text(leading!, style: PrepType.bodyLMedium.copyWith(color: PrepColors.text3)),
                        ),
                        const SizedBox(width: Space.s),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(text, style: PrepType.bodyL.copyWith(color: ink)),
                            if (note != null) ...[
                              const SizedBox(height: Space.s),
                              Text(note!, style: PrepType.label.copyWith(color: status ?? PrepColors.text2)),
                            ],
                          ],
                        ),
                      ),
                      if (mark != null && status != null) ...[
                        const SizedBox(width: Space.m),
                        StatusMark(mark, color: status),
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
  static const _padding = EdgeInsets.symmetric(horizontal: 18, vertical: Space.m);

  @override
  Widget build(BuildContext context) {
    if (ghost) {
      return ExcludeSemantics(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(_radius)),
              side: BorderSide(color: PrepColors.lineStrong),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: _padding,
              child: Text(text, style: PrepType.bodyL.copyWith(color: Colors.transparent)),
            ),
          ),
        ),
      );
    }
    final mark = _markFor(tone);
    final status = _statusOf(tone);
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
        child: _Tile(
          tone: tone,
          radius: _radius,
          child: Material(
            type: MaterialType.transparency,
            shape: _shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              focusColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Padding(
                  padding: _padding,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          text,
                          style: PrepType.bodyL.copyWith(color: tone == BoxTone.muted ? PrepColors.text2 : PrepColors.text),
                        ),
                      ),
                      if (mark != null && status != null) ...[
                        const SizedBox(width: Space.s),
                        StatusMark(mark, color: status, size: 20),
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
          padding: const EdgeInsets.symmetric(horizontal: Space.xxs, vertical: Space.xs),
          child: SizedBox(
            width: 88,
            height: 40,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: PrepColors.metalBottom.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(Radii.chip)),
                  side: BorderSide(color: PrepColors.lineStrong, width: 1.5),
                ),
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
          constraints: const BoxConstraints(minHeight: 60, minWidth: double.infinity),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(Radii.card)),
                side: BorderSide(color: PrepColors.lineStrong),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
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

/// A line someone says, set apart on a flat inset: what the interviewer asks, the line to rewrite,
/// or one way to say it. Flat (no rim, no shadow) so it never reads as a tile to tap.
class QuoteBlock extends StatelessWidget {
  const QuoteBlock({super.key, required this.label, required this.text, this.strong = false});

  final String label;
  final String text;

  /// The model answer reads in full white; everything else in the quieter grey.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label: $text',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Translucent, so the room's light shows through; flat, so it never reads as a tile.
          color: PrepColors.metalBottom.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: PrepType.meta.copyWith(color: PrepColors.text3)),
              const SizedBox(height: Space.xs),
              Text(text, style: PrepType.bodyLMedium.copyWith(color: strong ? PrepColors.text : PrepColors.text2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 4 dp progress line for the skill path. Decorative: the numbers beside it say the same.
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
              ColoredBox(color: PrepColors.line),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: PrepColors.accent, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eases a new exercise in: a short fade and a small slide from the right (Material's shared
/// axis). Nothing moves when the system asks for less motion.
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
