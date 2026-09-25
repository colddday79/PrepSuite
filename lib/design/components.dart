import 'package:flutter/material.dart';

import 'icons.dart';
import 'tokens.dart';

/// The one primary action on a screen: a warm light slab with dark text.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.control),
      side: BorderSide(color: enabled ? PrepColors.glassBorder : PrepColors.line),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56, minWidth: double.infinity),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: ShapeDecoration(
            shape: shape,
            color: enabled ? null : PrepColors.surface2,
            gradient: enabled
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [PrepColors.text, Color.lerp(PrepColors.text, PrepColors.accent, 0.18)!],
                  )
                : null,
          ),
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.m),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: PrepType.label.copyWith(color: enabled ? PrepColors.bg : PrepColors.text3),
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
class QuietButton extends StatelessWidget {
  const QuietButton(this.label, {super.key, required this.onPressed, this.icon, this.color = PrepColors.text2});

  final String label;
  final VoidCallback? onPressed;
  final PrepIcons? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tint = onPressed == null ? PrepColors.text3.withValues(alpha: 0.6) : color;
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(Radii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[PrepIcon(icon!, color: tint, size: 18), const SizedBox(width: Space.s)],
                Flexible(child: Text(label, style: PrepType.label.copyWith(color: tint))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 48 dp round icon control with a quiet fill.
class IconAction extends StatelessWidget {
  const IconAction(this.icon, {super.key, required this.label, required this.onPressed, this.plain = false});

  final PrepIcons icon;
  final String label;
  final VoidCallback onPressed;

  /// Plain actions sit on the page without a fill (the Home settings control).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: plain ? Colors.transparent : PrepColors.surface1.withValues(alpha: 0.7),
        shape: CircleBorder(side: plain ? BorderSide.none : const BorderSide(color: PrepColors.glassBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 48,
            child: Center(child: PrepIcon(icon, color: PrepColors.text2, size: plain ? 22 : 20)),
          ),
        ),
      ),
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: const SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: PrepColors.line)),
    );
  }
}

/// Top bar for the coach screens: a close control and a short status line.
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
            IconAction(PrepIcons.close, label: 'Close', onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

/// Multi-line text input on a solid surface (nothing sits behind it, so no glass).
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

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      key: fieldKey,
      controller: controller,
      autofocus: autofocus,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      textCapitalization: TextCapitalization.sentences,
      style: PrepType.bodyL,
      cursorColor: PrepColors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: PrepType.bodyL.copyWith(color: PrepColors.text3),
        filled: true,
        fillColor: PrepColors.surface1,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
        enabledBorder: border(PrepColors.lineStrong, 1),
        focusedBorder: border(PrepColors.accent, 1.5),
        border: border(PrepColors.lineStrong, 1),
      ),
    );
  }
}

/// A plain row with a hairline icon, a title, a meta line and a chevron.
class LinkRow extends StatelessWidget {
  const LinkRow({super.key, required this.icon, required this.title, required this.meta, required this.onTap});

  final PrepIcons icon;
  final String title;
  final String meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
                    Text(meta, style: PrepType.meta.copyWith(color: PrepColors.text3)),
                  ],
                ),
              ),
              if (onTap != null) const PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Headings are already large, so they grow at most 30% with the phone's text size while body
/// text scales fully. At the largest text sizes that keeps the controls under a heading on screen.
class HeadingScale extends StatelessWidget {
  const HeadingScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child);
}

/// Keeps reading width comfortable on tablets and open foldables; phones use their full width.
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.maxWidth = 560});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}
