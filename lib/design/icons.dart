import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

/// Hairline icons drawn on a 24-unit grid with one 1.5 stroke weight, so the set reads as one
/// family. Path data is ported unchanged from the native app (designsystem/Icons.kt).
enum PrepIcons {
  mic('M12 3.5a3 3 0 0 1 3 3v5a3 3 0 0 1 -6 0v-5a3 3 0 0 1 3 -3z M6.5 11.25a5.5 5.5 0 0 0 11 0 M12 16.75v3.75 M9 20.5h6'),
  write('M4.5 7h15 M4.5 12h15 M4.5 17h8.5'),
  clock('M12 3.75a8.25 8.25 0 1 1 0 16.5a8.25 8.25 0 1 1 0 -16.5z M12 7.75v4.5l3 1.75'),
  sliders('M4 7h8.5 M17.5 7h2.5 M15 4.5a2.5 2.5 0 1 1 0 5a2.5 2.5 0 1 1 0 -5z M4 17h2.5 M11.5 17h8.5 M9 14.5a2.5 2.5 0 1 1 0 5a2.5 2.5 0 1 1 0 -5z'),
  close('M6.5 6.5l11 11 M17.5 6.5l-11 11'),
  back('M14.5 5.5l-6.5 6.5l6.5 6.5'),
  chevron('M9.5 5.5l6.5 6.5l-6.5 6.5'),
  play('M8 5.75v12.5l10 -6.25z'),
  pause('M8.5 6v12 M15.5 6v12'),
  check('M5 12.5l4.5 4.5l9.5 -10'),
  speaker('M4.5 9.5h3l4.5 -4v13l-4.5 -4h-3z M15.5 9a4 4 0 0 1 0 6 M18 6.5a7.5 7.5 0 0 1 0 11'),
  speakerOff('M4.5 9.5h3l4.5 -4v13l-4.5 -4h-3z M16 9.5l5 5 M21 9.5l-5 5'),
  search('M10.5 4a6.5 6.5 0 1 1 0 13a6.5 6.5 0 1 1 0 -13z M15.5 15.5l4.5 4.5'),
  replay('M4.75 12a7.25 7.25 0 1 0 2.1 -5.1 M4.75 4.5v3.25h3.25'),
  keyboard('M3.5 6.5h17v11h-17z M7 10h0.01 M10.5 10h0.01 M14 10h0.01 M17 10h0.01 M8 14h8'),
  trash('M5 7h14 M10 4.5h4 M7 7l0.8 12.5h8.4l0.8 -12.5'),
  lock('M7.5 11v-3a4.5 4.5 0 0 1 9 0v3 M5.5 11h13v9h-13z'),
  shield('M12 3.5l7 3v5c0 4.5 -3 8 -7 9c-4 -1 -7 -4.5 -7 -9v-5z'),
  home('M3.5 10.5l8.5 -7l8.5 7 M5.5 9v11h4.5v-6h4v6h4.5v-11'),
  layers('M3 8l9 -5l9 5l-9 5z M3 12l9 5l9 -5 M3 16l9 5l9 -5'),
  arrowUpRight('M6 18l12 -12 M6 6h12v12'),
  user('M12 3.5a4 4 0 1 1 0 8a4 4 0 1 1 0 -8z M4.5 20v-1a7.5 5.5 0 0 1 15 0v1'),
  mail('M3.5 5.5h17v13h-17z M3.5 6l8.5 7l8.5 -7'),
  compass('M12 3a9 9 0 1 1 0 18a9 9 0 1 1 0 -18z M15.5 8.5l-2 5l-5 2l2 -5z'),
  target('M12 3a9 9 0 1 1 0 18a9 9 0 1 1 0 -18z M12 7a5 5 0 1 1 0 10a5 5 0 1 1 0 -10z M12 11v2'),
  calendar('M4.5 6h15v13.5h-15z M4.5 10h15 M8.5 3.5v4 M15.5 3.5v4'),
  chat('M4.5 5.5h15v10.5h-8.5l-4.5 3.5v-3.5h-2z M8 9.5h8 M8 12.5h5'),
  stop('M7 7h10v10h-10z'),
  edit('M4.5 19.5l1 -4l10 -10l3 3l-10 10z M13.5 7.5l3 3');

  const PrepIcons(this.data);
  final String data;

  static final Map<PrepIcons, Path> _cache = {};
  Path get path => _cache.putIfAbsent(this, () => parseSvgPathData(data));
}

/// Paints one hairline icon. Decorative by default; pass [semanticLabel] when it stands alone.
class PrepIcon extends StatelessWidget {
  const PrepIcon(this.icon, {super.key, this.color = const Color(0xFFF5EFE6), this.size = 24, this.semanticLabel});

  final PrepIcons icon;
  final Color color;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final painted = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _IconPainter(icon.path, color)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: painted);
    return Semantics(label: semanticLabel, image: true, child: painted);
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.path, this.color);

  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.scale(scale);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.path != path || old.color != color;
}
