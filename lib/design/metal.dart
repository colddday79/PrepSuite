import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'components.dart';
import 'icons.dart';
import 'tokens.dart';

/// The app's one material: satin metal. A same-hue vertical gradient, a 1 px light rim along the
/// top edge, a 1 px dark edge along the bottom, and (on hero cards only) a soft offset shadow and a
/// faint sheen. No blur, no coloured borders, no glows.
class MetalCard extends StatelessWidget {
  const MetalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.xl),
    this.radius = Radii.card,
    this.hero = false,
    this.onTap,
    this.semanticLabel,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Hero cards carry the drop shadow and the sheen.
  final bool hero;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// An optional tint laid over the metal (a drill result), at low strength.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    Widget body = CustomPaint(
      painter: _MetalPainter(radius: radius, hero: hero, tint: tint),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null) {
      body = Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, customBorder: shape, child: body),
      );
      body = FocusRing(radius: radius, child: body);
    }
    if (semanticLabel != null) {
      body = Semantics(
        button: onTap != null,
        label: semanticLabel,
        excludeSemantics: true,
        onTap: onTap,
        child: body,
      );
    }
    if (!hero) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [BoxShadow(color: Color(0x66000000), offset: Offset(0, 14), blurRadius: 32)],
      ),
      child: body,
    );
  }
}

class _MetalPainter extends CustomPainter {
  _MetalPainter({required this.radius, required this.hero, this.tint})
    : _top = PrepColors.metalTop,
      _bottom = PrepColors.metalBottom,
      _rim = PrepColors.rimLight;

  final double radius;
  final bool hero;
  final Color? tint;
  final Color _top;
  final Color _bottom;
  final Color _rim;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [_top, _bottom]),
    );
    if (tint != null) canvas.drawRRect(rrect, Paint()..color = tint!.withValues(alpha: 0.14));
    if (hero) {
      // A faint brushed sheen from the top-left corner: what reads as metal rather than plastic.
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topLeft,
            Offset(size.width * 0.6, size.height * 0.5),
            [const Color(0x0DFFFFFF), const Color(0x00FFFFFF)],
          ),
      );
      canvas.restore();
    }
    // Rims: light along the top, dark along the bottom, fading out down the sides.
    final inner = rrect.deflate(0.5);
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
          _rim,
          _rim.withValues(alpha: 0),
          const Color(0x00000000),
          PrepColors.rimDark,
        ], const [0, 0.35, 0.65, 1]),
    );
  }

  @override
  bool shouldRepaint(_MetalPainter old) =>
      old.radius != radius || old.hero != hero || old.tint != tint || old._top != _top || old._rim != _rim;
}

/// A round metal icon control (52 dp by default). [label] is what screen readers say. [active]
/// draws a thin accent ring; [filled] makes it the accent itself (the one hot control on screen).
class MetalDisc extends StatelessWidget {
  const MetalDisc(
    this.icon, {
    super.key,
    required this.label,
    required this.onPressed,
    this.size = 52,
    this.iconSize,
    this.active = false,
    this.filled = false,
    this.fill,
  });

  final PrepIcons icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double? iconSize;
  final bool active;
  final bool filled;

  /// Overrides the fill (the recording red).
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final hot = filled || fill != null;
    final bg = fill ?? (filled ? PrepColors.accent : PrepColors.surface2);
    final fg = hot ? PrepColors.onAccent : (enabled ? PrepColors.text : PrepColors.text3);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: FocusRing(
          radius: size / 2,
          child: Material(
            color: bg,
            shape: CircleBorder(
              side: BorderSide(color: active ? PrepColors.accentDeep : PrepColors.rimLight, width: active ? 1.5 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox.square(
                dimension: math.max(48, size),
                child: Center(child: PrepIcon(icon, color: fg, size: iconSize ?? size * 0.42)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Progress as a 270 degree arc on a hairline track, with optional ticks around it. Only for real
/// progress: drills done, time used, questions answered. [child] sits in the middle.
class ArcGauge extends StatelessWidget {
  const ArcGauge({
    super.key,
    required this.value,
    required this.size,
    this.child,
    this.ticks = false,
    this.stroke,
    this.semanticLabel,
    this.color,
  });

  final double value;
  final double size;
  final Widget? child;
  final bool ticks;
  final double? stroke;
  final String? semanticLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final gauge = TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: reduce ? Duration.zero : Motion.enter,
      curve: Motion.standard,
      builder: (context, v, child) => CustomPaint(
        painter: _ArcPainter(
          value: v,
          ticks: ticks,
          stroke: stroke ?? math.max(3, size * 0.05),
          track: PrepColors.line,
          fill: color ?? PrepColors.accent,
          tick: PrepColors.accentDeep,
        ),
        child: child,
      ),
      child: SizedBox.square(dimension: size, child: Center(child: child)),
    );
    if (semanticLabel == null) return gauge;
    return Semantics(label: semanticLabel, excludeSemantics: child == null, child: gauge);
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.value,
    required this.ticks,
    required this.stroke,
    required this.track,
    required this.fill,
    required this.tick,
  });

  final double value;
  final bool ticks;
  final double stroke;
  final Color track;
  final Color fill;
  final Color tick;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke / 2 - (ticks ? size.shortestSide * 0.07 : 0);
    final rect = Rect.fromCircle(center: c, radius: r);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, _start, _sweep, false, line..color = track);
    if (value > 0) canvas.drawArc(rect, _start, _sweep * value, false, line..color = fill);
    if (!ticks) return;
    const count = 48;
    final outer = size.shortestSide / 2;
    final inner = outer - size.shortestSide * 0.045;
    for (var i = 0; i <= count; i++) {
      final t = i / count;
      final a = _start + _sweep * t;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + dir * inner,
        c + dir * outer,
        Paint()
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = t <= value ? tick.withValues(alpha: 0.85) : track,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.value != value || old.ticks != ticks || old.fill != fill || old.track != track || old.stroke != stroke;
}

/// One tab in [FloatingTabBar].
class TabItem {
  const TabItem({required this.key, required this.icon, required this.label});

  final Key key;
  final PrepIcons icon;
  final String label;
}

/// The tab bar: a raised metal pill floating above the bottom edge, icons only (labels for screen
/// readers and as tooltips), the current tab an accent circle. The one place with a backdrop blur,
/// over real scrolling content.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key, required this.items, required this.index, required this.onSelect});

  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.l + 8, 0, Space.l + 8, bottom + Space.m),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PrepColors.surface2.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: PrepColors.rimLight),
            ),
            child: SizedBox(
              height: 68,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final (i, item) in items.indexed)
                    _Tab(item: item, selected: i == index, position: i, total: items.length, onTap: () => onSelect(i)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.selected, required this.position, required this.total, required this.onTap});

  final TabItem item;
  final bool selected;
  final int position;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '${item.label}, tab ${position + 1} of $total',
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        child: FocusRing(
          radius: 26,
          child: InkWell(
            key: item.key,
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: Motion.fade,
              curve: Motion.standard,
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: selected ? PrepColors.accent : null, shape: BoxShape.circle),
              child: Center(
                child: PrepIcon(item.icon, color: selected ? PrepColors.onAccent : PrepColors.text2, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How much room the floating tab bar takes at the bottom, so lists can pad under it.
double floatingTabBarInset(BuildContext context) => 68 + Space.m + MediaQuery.paddingOf(context).bottom + Space.l;
