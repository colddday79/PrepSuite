import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'components.dart';
import 'glass.dart';
import 'icons.dart';
import 'tokens.dart';

/// The app's one material: smoked glass over satin metal. A translucent same-hue gradient that lets
/// the lit room ([AmbientBackdrop]) through, a sheen, a bright specular top edge, an inner line for
/// the glass's thickness, a dark bottom edge, and on hero cards a soft offset shadow. No coloured
/// borders and no glows.
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
    // Smoked glass over metal: see lib/design/glass.dart.
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    paintGlass(canvas, rrect, top: _top, bottom: _bottom, hero: hero, tint: tint);
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
    this.tickColor,
  });

  final double value;
  final double size;
  final Widget? child;
  final bool ticks;
  final double? stroke;
  final String? semanticLabel;
  final Color? color;

  /// The passed ticks; defaults to the accent as text ([PrepColors.accentDeep]).
  final Color? tickColor;

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
          tick: tickColor ?? PrepColors.accentDeep,
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
      old.value != value ||
      old.ticks != ticks ||
      old.fill != fill ||
      old.track != track ||
      old.tick != tick ||
      old.stroke != stroke;
}

/// One tab in [FloatingTabBar].
class TabItem {
  const TabItem({required this.key, required this.icon, required this.label});

  final Key key;
  final PrepIcons icon;
  final String label;
}

/// The tab bar: a raised glass pill floating above the bottom edge. The current tab is an accent
/// pill with its icon and name; the others are icons only (their names are tooltips and what screen
/// readers say). Names drop out together when the widest would not fit (narrow phone, large text).
/// The one place with a backdrop blur, over real scrolling content.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key, required this.items, required this.index, required this.onSelect});

  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  static const double _inset = Space.s;
  static const double _disc = 52;
  static const double _pillPad = 14;
  static const double _icon = 22;

  static TextStyle get _labelStyle => PrepType.label.copyWith(color: PrepColors.onAccent);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, bottom + Space.m),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: CustomPaint(
            painter: _GlassBarPainter(top: PrepColors.surface2, bottom: PrepColors.metalTop),
            child: SizedBox(
              height: 68,
              child: LayoutBuilder(
                builder: (context, box) {
                  var widest = 0.0;
                  for (final item in items) {
                    final painter = TextPainter(
                      text: TextSpan(text: item.label, style: _labelStyle),
                      textDirection: TextDirection.ltr,
                      textScaler: scaler,
                      maxLines: 1,
                    )..layout();
                    if (painter.width > widest) widest = painter.width;
                    painter.dispose();
                  }
                  final room = box.maxWidth - 2 * _inset - (items.length - 1) * _disc;
                  final named = 2 * _pillPad + _icon + Space.s + widest <= room;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _inset),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final (i, item) in items.indexed)
                          _Tab(
                            item: item,
                            selected: i == index,
                            named: named,
                            scaler: scaler,
                            position: i,
                            total: items.length,
                            onTap: () => onSelect(i),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tab bar's pane: translucent raised metal over the live blur, with the glass's specular top
/// edge.
class _GlassBarPainter extends CustomPainter {
  const _GlassBarPainter({required this.top, required this.bottom});

  final Color top;
  final Color bottom;

  @override
  void paint(Canvas canvas, Size size) => paintGlass(
    canvas,
    RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)),
    top: top,
    bottom: bottom,
  );

  @override
  bool shouldRepaint(_GlassBarPainter old) => old.top != top || old.bottom != bottom;
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.named,
    required this.scaler,
    required this.position,
    required this.total,
    required this.onTap,
  });

  final TabItem item;
  final bool selected;
  final bool named;
  final TextScaler scaler;
  final int position;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = still ? Duration.zero : Motion.fade;
    final showName = selected && named;
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
          radius: FloatingTabBar._disc / 2,
          child: Material(
            type: MaterialType.transparency,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: item.key,
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: AnimatedContainer(
                duration: duration,
                curve: Motion.standard,
                height: FloatingTabBar._disc,
                constraints: const BoxConstraints(minWidth: FloatingTabBar._disc),
                padding: EdgeInsets.symmetric(horizontal: showName ? FloatingTabBar._pillPad : 0),
                decoration: ShapeDecoration(
                  color: selected ? PrepColors.accent : PrepColors.accent.withValues(alpha: 0),
                  shape: const StadiumBorder(),
                ),
                child: AnimatedSize(
                  duration: duration,
                  curve: Motion.standard,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PrepIcon(
                        item.icon,
                        color: selected ? PrepColors.onAccent : PrepColors.text2,
                        size: FloatingTabBar._icon,
                      ),
                      if (showName) ...[
                        const SizedBox(width: Space.s),
                        Text(item.label, style: FloatingTabBar._labelStyle, textScaler: scaler, maxLines: 1),
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

/// How much room the floating tab bar takes at the bottom, so lists can pad under it.
double floatingTabBarInset(BuildContext context) => 68 + Space.m + MediaQuery.paddingOf(context).bottom + Space.l;

/// A tappable metal card. The metal is painted beneath the ink, so the press tint shows on top of
/// it (a [MetalCard] with [MetalCard.onTap] keeps its ink under the paint). [semanticLabel] is
/// all a screen reader hears; [tapHint] says what a tap does.
class MetalTile extends StatelessWidget {
  const MetalTile({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.tapHint,
    this.padding = const EdgeInsets.all(Space.xl),
    this.radius = Radii.card,
    this.hero = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;
  final String? tapHint;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      onTap: onTap,
      onTapHint: onTap == null ? null : tapHint,
      excludeSemantics: true,
      child: FocusRing(
        radius: radius,
        child: MetalCard(
          hero: hero,
          radius: radius,
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: shape,
              focusColor: Colors.transparent,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two or three short choices on one recessed track; the chosen one is a raised metal chip that
/// slides across. Tapping any segment, the chosen one too, calls [onSelect], so a caller can clear
/// an optional answer. Screen readers hear checked or unchecked options in one group. [keys] go
/// on each segment's tap target; [selectedHint] says what tapping the chosen one does.
class MetalSegments extends StatelessWidget {
  const MetalSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.keys,
    this.selectedHint,
  });

  final List<String> labels;
  final int? selected;
  final ValueChanged<int> onSelect;
  final List<Key>? keys;
  final String? selectedHint;

  static const double _inset = Space.xs;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final count = labels.length;
    final chosen = selected;
    final chip = BorderRadius.circular(Radii.control);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PrepColors.metalBottom.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(Radii.control + _inset),
        border: Border.all(color: PrepColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_inset),
        child: IntrinsicHeight(
          child: Stack(
            children: [
              if (chosen != null)
                Positioned.fill(
                  child: AnimatedAlign(
                    alignment: Alignment(count < 2 ? 0 : -1 + 2 * chosen / (count - 1), 0),
                    duration: reduce ? Duration.zero : Motion.fade,
                    curve: Motion.standard,
                    child: FractionallySizedBox(
                      widthFactor: 1 / count,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: PrepColors.surface2.withValues(alpha: 0.9),
                          borderRadius: chip,
                          border: Border.all(color: PrepColors.rimLight),
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: Semantics(
                        container: true,
                        button: true,
                        inMutuallyExclusiveGroup: true,
                        checked: i == chosen,
                        label: labels[i],
                        onTap: () => onSelect(i),
                        onTapHint: i == chosen ? selectedHint : null,
                        excludeSemantics: true,
                        child: FocusRing(
                          radius: Radii.control,
                          gap: -2,
                          child: Material(
                            type: MaterialType.transparency,
                            borderRadius: chip,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: keys?[i],
                              onTap: () => onSelect(i),
                              focusColor: Colors.transparent,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 48),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
                                  child: Center(
                                    child: Text(
                                      labels[i],
                                      textAlign: TextAlign.center,
                                      style: PrepType.label.copyWith(
                                        color: i == chosen ? PrepColors.text : PrepColors.text2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
