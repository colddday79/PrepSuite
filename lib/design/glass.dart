import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The lit room behind the glass: the canvas, a warm key light falling from the top-right corner
/// in the theme accent, a faint bounce low on the left, and a vignette. Glass cards over it pick
/// up that light through their smoked fill, the way the panels in the owner's references sit over
/// a dim, lamp-lit room. The light is smooth, so no live blur is needed behind the cards.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key, required this.child, this.intensity = 1});

  final Widget child;

  /// 1 is the normal room; lower it on screens that need more calm (long text).
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AmbientPainter(
        canvas: PrepColors.bg,
        accent: PrepColors.accent,
        intensity: intensity,
      ),
      child: child,
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({required this.canvas, required this.accent, required this.intensity});

  final Color canvas;
  final Color accent;
  final double intensity;

  @override
  void paint(Canvas canvas_, Size size) {
    final rect = Offset.zero & size;
    final w = size.width, h = size.height;
    final reach = math.max(w, h);
    canvas_.drawRect(rect, Paint()..color = canvas);

    // Key light: high on the right, warm, like a lamp just out of frame.
    final key = Offset(w * 1.02, -h * 0.04);
    canvas_.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(key, reach * 0.78, [
          accent.withValues(alpha: 0.2 * intensity),
          accent.withValues(alpha: 0.07 * intensity),
          accent.withValues(alpha: 0),
        ], const [0, 0.42, 1]),
    );

    // Bounce: the same light, much weaker, coming back off the floor on the left.
    final bounce = Offset(-w * 0.12, h * 0.9);
    canvas_.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(bounce, reach * 0.6, [
          accent.withValues(alpha: 0.07 * intensity),
          accent.withValues(alpha: 0),
        ]),
    );

    // Vignette, so the eye stays in the middle and the corners fall into shadow.
    canvas_.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(Offset(w * 0.5, h * 0.42), reach * 0.85, [
          const Color(0x00000000),
          const Color(0x00000000),
          const Color(0x59000000),
        ], const [0, 0.55, 1]),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.canvas != canvas || old.accent != accent || old.intensity != intensity;
}

/// Paints smoked glass over metal in [rrect]: a translucent fill that lets the room's light through,
/// a diagonal sheen, a bright specular edge along the top that fades down the sides, a second
/// faint line just inside it for the edge's thickness, and a dark edge along the bottom.
void paintGlass(
  Canvas canvas,
  RRect rrect, {
  required Color top,
  required Color bottom,
  bool hero = false,
  Color? tint,
}) {
  final rect = rrect.outerRect;
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
        top.withValues(alpha: hero ? 0.66 : 0.72),
        bottom.withValues(alpha: hero ? 0.8 : 0.86),
      ]),
  );
  if (tint != null) canvas.drawRRect(rrect, Paint()..color = tint.withValues(alpha: 0.14));

  canvas.save();
  canvas.clipRRect(rrect);
  // Sheen: light caught across the top-left of the pane.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        Offset(rect.left + rect.width * 0.55, rect.top + math.min(rect.height, rect.width) * 0.55),
        [Color.fromRGBO(255, 255, 255, hero ? 0.085 : 0.06), const Color(0x00FFFFFF)],
      ),
  );
  canvas.restore();

  // The specular edge: bright along the top, gone by a third of the way down, dark at the bottom.
  canvas.drawRRect(
    rrect.deflate(0.6),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
        const Color(0x38FFFFFF),
        const Color(0x00FFFFFF),
        const Color(0x00000000),
        const Color(0x80000000),
      ], const [0, 0.32, 0.7, 1]),
  );
  // The glass's thickness: one faint line just inside the top edge.
  canvas.drawRRect(
    rrect.deflate(2.2),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
        const Color(0x12FFFFFF),
        const Color(0x00FFFFFF),
      ], const [0, 0.18]),
  );
}
