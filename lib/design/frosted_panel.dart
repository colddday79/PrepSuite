import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The one piece of glass: a panel set over the lower edge of the presence. It blurs the light
/// behind it, lifts the blurred copy so thin gold rings still read as light rather than smudge,
/// then tints it. Use it only where the presence actually sits behind.
class FrostedPanel extends StatelessWidget {
  const FrostedPanel({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(Space.xxl, Space.xxl, Space.xxl, Space.m)});

  final Widget child;
  final EdgeInsets padding;

  // Blurring spreads the thin gold rings thin; lift the frosted copy so they still read as light.
  static final ui.ImageFilter _frost = ui.ImageFilter.compose(
    outer: const ui.ColorFilter.matrix(<double>[
      1.6, 0, 0, 0, 0, //
      0, 1.6, 0, 0, 0, //
      0, 0, 1.6, 0, 0, //
      0, 0, 0, 1, 0, //
    ]),
    inner: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7, tileMode: TileMode.clamp),
  );

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(Radii.sheet));
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: _frost,
        child: CustomPaint(
          foregroundPainter: const _EdgeLight(),
          child: ColoredBox(
            color: PrepColors.glassBg,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// A 1 dp light catch on the top edge that runs into the corners and fades out.
class _EdgeLight extends CustomPainter {
  const _EdgeLight();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Radii.sheet));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PrepColors.cardHighlight, Color(0x00FFF4E0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, Radii.sheet)),
    );
  }

  @override
  bool shouldRepaint(_EdgeLight oldDelegate) => false;
}
