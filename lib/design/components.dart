import 'package:flutter/material.dart';

import 'icons.dart';
import 'tokens.dart';

/// A 2 dp gold ring drawn [gap] outside [child] while a control inside it has keyboard, D-pad or
/// switch-access focus. Touch input never shows it. Wrap any custom tappable in it (the record
/// button, a tappable row) so focus looks the same everywhere.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child, this.radius = Radii.control, this.gap = 3});

  final Widget child;

  /// The corner radius of [child]; the ring follows it at [gap].
  final double radius;

  /// Space between the child's edge and the ring. Negative values draw the ring inside, for
  /// full-bleed rows.
  final double gap;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;
  bool _keyboard = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode mode) {
    final keyboard = mode == FocusHighlightMode.traditional;
    if (keyboard != _keyboard && mounted) setState(() => _keyboard = keyboard);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      child: CustomPaint(
        foregroundPainter: _focused && _keyboard ? _RingPainter(widget.radius, widget.gap) : null,
        child: widget.child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.radius, this.gap);

  final double radius;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    // The stroke is centred on the path, so push it out by half its width.
    const stroke = 2.0;
    final spread = gap + stroke / 2;
    final rect = (Offset.zero & size).inflate(spread);
    final r = (radius + spread).clamp(0.0, rect.shortestSide / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = PrepColors.focus,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.radius != radius || old.gap != gap;
}

/// The one primary action on a screen: a solid warm light slab with dark text.
///
/// Pressing darkens the fill and settles it to [Motion.pressScale] within [Motion.press]
/// (no scale when the system asks for less motion). Disabled keeps a readable label on a dark slab.
/// [busy] shows a small spinner and ignores taps while the label stays in place.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton(this.label, {super.key, required this.onPressed, this.icon, this.busy = false});

  final String label;
  final VoidCallback? onPressed;

  /// An optional hairline icon before the label.
  final PrepIcons? icon;
  final bool busy;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  // PrepColors.text 10% of the way to bg: a visible dip that keeps the label at 13:1.
  static const _pressedFill = Color(0xFFDED8D0);
  static const _shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control)));
  static const _disabledShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(Radii.control)),
    side: BorderSide(color: PrepColors.lineStrong),
  );

  bool _pressed = false;

  bool get _interactive => widget.onPressed != null && !widget.busy;

  @override
  void didUpdateWidget(PrimaryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_interactive) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final fill = !enabled ? PrepColors.surface2 : (_pressed ? _pressedFill : PrepColors.text);
    final ink = enabled ? PrepColors.bg : PrepColors.text3;
    final duration = _pressed ? Motion.press : Motion.fade;
    return Semantics(
      container: true,
      button: true,
      enabled: _interactive,
      value: widget.busy ? 'In progress' : null,
      child: FocusRing(
        child: AnimatedScale(
          scale: _pressed && !still ? Motion.pressScale : 1,
          duration: duration,
          curve: Motion.standard,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: fill),
            duration: duration,
            curve: Motion.standard,
            builder: (context, color, child) => DecoratedBox(
              decoration: ShapeDecoration(color: color, shape: enabled ? _shape : _disabledShape),
              child: child,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _interactive ? widget.onPressed : null,
                onHighlightChanged: (down) {
                  if (down != _pressed) setState(() => _pressed = down && _interactive);
                },
                customBorder: _shape,
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56, minWidth: double.infinity),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.m),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.busy)
                          ExcludeSemantics(
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: ink, backgroundColor: Colors.transparent),
                            ),
                          )
                        else if (widget.icon != null)
                          PrepIcon(widget.icon!, color: ink, size: 18),
                        if (widget.busy || widget.icon != null) const SizedBox(width: Space.s),
                        Flexible(
                          child: Text(widget.label, textAlign: TextAlign.center, style: PrepType.button.copyWith(color: ink)),
                        ),
                      ],
                    ),
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

/// A text action with an optional hairline icon. No fill, so it never competes with the primary.
/// At least 48 by 48 dp; pressing lays a warm tint under the label.
class QuietButton extends StatelessWidget {
  const QuietButton(this.label, {super.key, required this.onPressed, this.icon, this.color = PrepColors.text2});

  final String label;
  final VoidCallback? onPressed;
  final PrepIcons? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // Disabled stays readable (text3 is 5.3:1 or better on every surface) and semantics say why.
    final tint = enabled ? color : PrepColors.text3;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      child: FocusRing(
        child: Material(
          type: MaterialType.transparency,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            focusColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[PrepIcon(icon!, color: tint, size: 18), const SizedBox(width: Space.s)],
                    Flexible(child: Text(label, style: PrepType.label.copyWith(color: tint))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 48 dp round icon control with a quiet fill. [label] is what screen readers say.
class IconAction extends StatelessWidget {
  const IconAction(this.icon, {super.key, required this.label, required this.onPressed, this.plain = false});

  final PrepIcons icon;
  final String label;
  final VoidCallback onPressed;

  /// Plain actions sit on the page without a fill (the Home settings control).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    // The label lives on the same node as the tap action, so TalkBack can activate it.
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: FocusRing(
        radius: 24,
        child: Material(
          color: plain ? Colors.transparent : PrepColors.surface1.withValues(alpha: 0.7),
          shape: CircleBorder(side: plain ? BorderSide.none : const BorderSide(color: PrepColors.glassBorder)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            focusColor: Colors.transparent,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 48,
              child: Center(child: PrepIcon(icon, color: PrepColors.text2, size: plain ? 22 : 20)),
            ),
          ),
        ),
      ),
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0, this.color = PrepColors.line});

  final double indent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: color)),
    );
  }
}

/// Top bar for the coach screens: a short status line and a close control.
class CoachTopBar extends StatelessWidget {
  const CoachTopBar({super.key, required this.onClose, this.status});

  final VoidCallback onClose;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Row(
          children: [
            Expanded(child: Text(status ?? '', style: PrepType.meta, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Space.m),
            IconAction(PrepIcons.close, label: 'Close', onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

/// Multi-line text input on a solid surface (nothing sits behind it, so no glass).
///
/// [label] adds a visible label above the field (forms); [errorText] shows below it in words,
/// never colour alone. The gold border is the focus state for touch and keyboard alike.
class PrepTextField extends StatelessWidget {
  const PrepTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.minLines = 1,
    this.maxLines = 4,
    this.autofocus = false,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
    this.fieldKey,
    this.label,
    this.errorText,
    this.keyboardType,
    this.focusNode,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final int minLines;
  final int maxLines;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;
  final String? label;
  final String? errorText;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: color, width: width),
        );
    final field = TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.sentences,
      style: PrepType.bodyL.copyWith(color: enabled ? PrepColors.text : PrepColors.text3),
      cursorColor: PrepColors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: PrepType.bodyL.copyWith(color: PrepColors.text3),
        errorText: errorText,
        errorStyle: PrepType.meta.copyWith(color: PrepColors.danger),
        errorMaxLines: 3,
        filled: true,
        fillColor: PrepColors.surface1,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
        enabledBorder: border(PrepColors.lineStrong, 1),
        focusedBorder: border(PrepColors.accent, 1.5),
        disabledBorder: border(PrepColors.line, 1),
        errorBorder: border(PrepColors.danger, 1),
        focusedErrorBorder: border(PrepColors.danger, 1.5),
        border: border(PrepColors.lineStrong, 1),
      ),
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label!, style: PrepType.label.copyWith(color: PrepColors.text2)),
        const SizedBox(height: Space.s),
        field,
      ],
    );
  }
}

/// A plain row with a hairline icon, a title, a meta line and a chevron. Screen readers hear the
/// title and meta as one item, and it is a button only when [onTap] is set.
class LinkRow extends StatelessWidget {
  const LinkRow({super.key, required this.icon, required this.title, this.meta = '', required this.onTap});

  final PrepIcons icon;
  final String title;
  final String meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: FocusRing(
          radius: Radii.control,
          gap: -Space.xs,
          child: InkWell(
            onTap: onTap,
            focusColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.m),
                child: Row(
                  children: [
                    PrepIcon(icon, color: PrepColors.text2),
                    const SizedBox(width: Space.l),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: PrepType.bodyLMedium),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: Space.xxs),
                            Text(meta, style: PrepType.meta.copyWith(color: PrepColors.text3)),
                          ],
                        ],
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: Space.m),
                      const PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
