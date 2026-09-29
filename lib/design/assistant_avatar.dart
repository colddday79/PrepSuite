import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant.dart';
import 'hologram.dart';

/// What the assistant is doing, which sets its face.
enum AssistantMood {
  /// Resting: soft eyes that blink and glance, a small smile.
  idle,

  /// The person is talking: attentive eyes, the mouth becomes a live sound wave.
  listening,

  /// The assistant is talking: the mouth opens with the voice level.
  speaking,

  /// Waiting on the coach: eyes look up, three dots pulse.
  thinking,

  /// Greeting or celebrating: ^ ^ eyes and a wide smile.
  happy,
}

/// Where the visor sits in the render square (normalised, origin top-left). Measured by
/// tools/blender/models/assistant.py (face.json); the camera and head never move between variants.
const Rect kAssistantVisor = Rect.fromLTRB(0.29219, 0.20526, 0.70781, 0.48411);
const double _visorExponent = 3.1;

/// The assistant: a Blender-rendered robot whose face is drawn live on its visor, so the mouth moves
/// with the voice and the eyes blink and react. Behind it a quiet holographic halo and floor ring
/// keep the original Jarvis feel. The orb look shows the gold hologram instead.
///
/// [size] is the side of the square the render fills; the robot's feet sit near its bottom edge.
class AssistantAvatar extends StatefulWidget {
  const AssistantAvatar({
    super.key,
    required this.look,
    required this.size,
    this.mood = AssistantMood.idle,
    this.level,
    this.hud = true,
    this.semanticLabel,
  });

  /// Tests switch the per-frame animation off so fixed pumps stay deterministic.
  static bool live = true;

  final AssistantLook look;
  final double size;
  final AssistantMood mood;

  /// Voice level 0..1: the assistant's own voice while speaking, the microphone while listening.
  final ValueListenable<double>? level;

  /// Draw the holographic halo and floor ring.
  final bool hud;

  final String? semanticLabel;

  @override
  State<AssistantAvatar> createState() => _AssistantAvatarState();
}

class _AssistantAvatarState extends State<AssistantAvatar> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = _FaceClock();
  _Layers? _layers;
  int _requested = 0;
  int _bucket = 0;
  AssistantLook? _loaded;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.level?.addListener(_onLevel);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
    _syncTicker();
  }

  @override
  void didUpdateWidget(AssistantAvatar old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) {
      old.level?.removeListener(_onLevel);
      widget.level?.addListener(_onLevel);
    }
    if (old.look != widget.look || old.size != widget.size) _load();

    if (old.mood != widget.mood) _clock.moodChanged(widget.mood);
    _syncTicker();
  }

  @override
  void dispose() {
    widget.level?.removeListener(_onLevel);
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  bool get _animate => AssistantAvatar.live && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _syncTicker() {
    if (_animate && widget.look.isRobot) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
      _clock.still();
    }
  }

  void _tick(Duration elapsed) => _clock.advance(elapsed, widget.mood, widget.level?.value ?? 0);

  void _onLevel() {
    if (!_ticker.isActive) _clock.advance(null, widget.mood, widget.level?.value ?? 0);
  }

  void _load() {
    final look = widget.look;
    if (!look.isRobot) return;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final px = _AssetCache.bucket(widget.size * ratio);
    // While a size animates, keep the sharpest layers already decoded for this look.
    if (look == _loaded && px <= _bucket) return;
    _loaded = look;
    _bucket = px;
    final ticket = ++_requested;
    _Layers.load(look, px).then((layers) {
      if (mounted && ticket == _requested) setState(() => _layers = layers);
    }, onError: (Object e) => debugPrint('Assistant images unavailable: $e'));
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final label = widget.semanticLabel ?? 'Your assistant, ${look.name}';
    if (!look.isRobot) {
      return Semantics(
        label: label,
        image: true,
        child: SizedBox.square(
          dimension: widget.size,
          // The hologram paints its own dark room: keep it a round lens, not a square.
          child: ClipOval(child: HologramStage(size: widget.size * 0.86, level: widget.level)),
        ),
      );
    }
    return Semantics(
      label: label,
      image: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _AssistantPainter(
              layers: _layers,
              look: look,
              mood: widget.mood,
              clock: _clock,
              hud: widget.hud,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Time, blinking, gaze and level smoothing
// ---------------------------------------------------------------------------

class _FaceClock extends ChangeNotifier {
  final _random = math.Random();
  double t = 0;
  double level = 0;
  double blink = 0;
  Offset gaze = Offset.zero;
  Offset _gazeTarget = Offset.zero;
  double _nextBlink = 2.2;
  double _nextGaze = 1.5;
  double _moodSince = 0;
  Duration? _last;
  bool _disposed = false;

  /// Seconds since the mood last changed, for small entrance moves.
  double get sinceMood => t - _moodSince;

  void moodChanged(AssistantMood mood) => _moodSince = t;

  void still() {
    blink = 0;
    gaze = Offset.zero;
    _notify();
  }

  void advance(Duration? elapsed, AssistantMood mood, double target) {
    var dt = 1 / 60;
    if (elapsed != null) {
      final last = _last;
      dt = last == null ? 0 : ((elapsed - last).inMicroseconds / 1e6).clamp(0.0, 0.1);
      _last = elapsed;
      t += dt;
    }
    // Rise fast, fall a little slower, so the mouth follows syllables without chattering.
    final k = target > level ? 0.55 : 0.28;
    level += (target.clamp(0.0, 1.0) - level) * k;

    if (t >= _nextBlink) {
      final p = (t - _nextBlink) / 0.16;
      blink = p >= 1 ? 0 : math.sin(p * math.pi);
      if (p >= 1) {
        // Now and then a double blink, like a person.
        _nextBlink = t + (_random.nextDouble() < 0.18 ? 0.22 : 2.4 + _random.nextDouble() * 3.4);
      }
    }
    if (t >= _nextGaze) {
      _gazeTarget = mood == AssistantMood.idle
          ? Offset(_random.nextDouble() * 2 - 1, (_random.nextDouble() * 2 - 1) * 0.6) * 0.8
          : Offset.zero;
      _nextGaze = t + 1.6 + _random.nextDouble() * 2.8;
    }
    final aim = switch (mood) {
      AssistantMood.thinking => const Offset(0.7, -0.75),
      AssistantMood.listening => const Offset(0, 0.1),
      _ => _gazeTarget,
    };
    gaze = Offset.lerp(gaze, aim, 0.08)!;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Rendered layers
// ---------------------------------------------------------------------------

class _Layers {
  const _Layers(this.body, this.glass, this.glow);

  final ui.Image body;
  final ui.Image glass;
  final ui.Image glow;

  static Future<_Layers> load(AssistantLook look, int px) async {
    final images = await Future.wait([
      _AssetCache.image(look.bodyAsset, px),
      _AssetCache.image(look.glassAsset, px),
      _AssetCache.image(look.glowAsset, (px / 2).round()),
    ]);
    return _Layers(images[0], images[1], images[2]);
  }
}

/// Decoded render layers, shared between avatars and decoded at about the size they are shown.
abstract final class _AssetCache {
  static final Map<String, Future<ui.Image>> _images = {};

  /// Decode sizes step in 192 px so a handful of sizes share one decode.
  static int bucket(double px) => (((px / 192).ceil()) * 192).clamp(192, 1152);

  static Future<ui.Image> image(String asset, int px) {
    return _images.putIfAbsent('$asset@$px', () async {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: px, targetHeight: px);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
  }
}

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

class _AssistantPainter extends CustomPainter {
  _AssistantPainter({required this.layers, required this.look, required this.mood, required this.clock, required this.hud})
      : super(repaint: clock);

  final _Layers? layers;
  final AssistantLook look;
  final AssistantMood mood;
  final _FaceClock clock;
  final bool hud;

  double get _energy {
    final t = clock.t;
    final l = clock.level;
    return switch (mood) {
      AssistantMood.idle => 0.55 + 0.1 * math.sin(t * 1.4),
      AssistantMood.listening => 0.6 + 0.4 * l,
      AssistantMood.speaking => 0.62 + 0.38 * l,
      AssistantMood.thinking => 0.45 + 0.35 * (0.5 + 0.5 * math.sin(t * 4.2)),
      AssistantMood.happy => 0.85,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final t = clock.t;
    if (hud) _paintHud(canvas, s, t);

    final layers = this.layers;
    if (layers == null) return;

    // A slow hover and the smallest sway, so the robot never looks frozen.
    final float = math.sin(t * 2 * math.pi / 4.2) * s * 0.012;
    final sway = math.sin(t * 2 * math.pi / 6.8) * 0.012;
    canvas.save();
    canvas.translate(s / 2, s / 2 + float);
    canvas.rotate(sway);
    canvas.translate(-s / 2, -s / 2);

    final box = Offset.zero & size;
    final smoothing = Paint()..filterQuality = FilterQuality.medium;
    _drawImage(canvas, layers.body, box, smoothing);
    _paintFace(canvas, s);
    // Light layers carry their own transparency (baked from renders on black), so they are
    // drawn normally: they add light and leave the page untouched everywhere else.
    _drawImage(canvas, layers.glass, box, Paint()..filterQuality = FilterQuality.medium);
    _drawImage(canvas, layers.glow, box, Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, _energy.clamp(0.0, 1.0)));
    canvas.restore();
  }

  void _drawImage(Canvas canvas, ui.Image image, Rect dst, Paint paint) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, paint);
  }

  // The Jarvis part: a thin halo of arcs and ticks behind the head and a hover ring under the feet.
  void _paintHud(Canvas canvas, double s, double t) {
    final glow = look.glow;
    final busy = mood == AssistantMood.thinking;
    final speed = busy ? 1.1 : 0.22;
    final lift = busy ? 0.18 : 0.0;

    final head = Offset(s * 0.5, s * 0.345);
    canvas.drawCircle(
      head,
      s * 0.46,
      Paint()
        ..shader = ui.Gradient.radial(head, s * 0.46, [
          glow.withValues(alpha: 0.2 + lift),
          glow.withValues(alpha: 0.05),
          glow.withValues(alpha: 0),
        ], const [0, 0.55, 1]),
    );

    final r = s * 0.41;
    final ticks = Paint()
      ..color = glow.withValues(alpha: 0.16 + lift * 0.5)
      ..strokeWidth = math.max(1, s * 0.0022)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 72; i++) {
      final a = i / 72 * 2 * math.pi + t * speed * 0.35;
      final len = i % 6 == 0 ? s * 0.016 : s * 0.007;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(head + dir * r, head + dir * (r + len), ticks);
    }
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, s * 0.004)
      ..color = glow.withValues(alpha: 0.42 + lift);
    final rect = Rect.fromCircle(center: head, radius: r - s * 0.018);
    for (final (start, sweep, dir) in const [(0.2, 0.7, 1.0), (2.3, 0.45, 1.0), (4.1, 1.1, 1.0), (1.2, 0.3, -1.6)]) {
      canvas.drawArc(rect, start + t * speed * dir, sweep, false, arc);
    }

    final floor = Offset(s * 0.5, s * 0.925);
    final rx = s * 0.3, ry = s * 0.05;
    // The pool of light under the hover ring: a radial glow squashed into the floor's perspective.
    canvas.save();
    canvas.translate(floor.dx, floor.dy);
    canvas.scale(1, ry / rx);
    canvas.drawCircle(
      Offset.zero,
      rx * 1.3,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, rx * 1.3, [
          glow.withValues(alpha: 0.32 + lift),
          glow.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, s * 0.003)
      ..color = glow.withValues(alpha: 0.55);
    canvas.drawOval(Rect.fromCenter(center: floor, width: rx * 2, height: ry * 2), ring);
    final dashes = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, s * 0.0045)
      ..strokeCap = StrokeCap.round
      ..color = glow.withValues(alpha: 0.5);
    final outer = Rect.fromCenter(center: floor, width: rx * 2.7, height: ry * 2.7);
    for (var i = 0; i < 16; i++) {
      canvas.drawArc(outer, i / 16 * 2 * math.pi + t * speed, 0.16, false, dashes);
    }
  }

  // The face on the visor: eyes and mouth in the glow colour, with a soft bloom, clipped to the glass.
  void _paintFace(Canvas canvas, double s) {
    final visor = Rect.fromLTRB(
      kAssistantVisor.left * s,
      kAssistantVisor.top * s,
      kAssistantVisor.right * s,
      kAssistantVisor.bottom * s,
    ).deflate(s * 0.008);
    canvas.save();
    canvas.clipPath(_superellipse(visor, _visorExponent));

    final glow = look.glow;
    final t = clock.t;
    final l = clock.level;

    // The screen is "on": a faint wash and scan lines.
    canvas.drawRect(
      visor,
      Paint()
        ..shader = ui.Gradient.radial(visor.center, visor.width * 0.6, [
          glow.withValues(alpha: 0.06),
          glow.withValues(alpha: 0.0),
        ]),
    );
    final scan = Paint()
      ..color = glow.withValues(alpha: 0.035)
      ..strokeWidth = math.max(0.6, s * 0.0012);
    final step = math.max(2.5, s * 0.009);
    for (var y = visor.top; y < visor.bottom; y += step) {
      canvas.drawLine(Offset(visor.left, y), Offset(visor.right, y), scan);
    }

    // Three passes per feature: a wide halo, a tight saturated glow and a bright core.
    final core = Color.lerp(glow, const Color(0xFFFFFFFF), 0.28)!;
    final halo = Paint()
      ..color = glow.withValues(alpha: 0.45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, visor.height * 0.12);
    final bloom = Paint()
      ..color = glow
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, visor.height * 0.035);
    final solid = Paint()..color = core;

    void shape(void Function(Paint paint) draw) {
      draw(halo);
      draw(bloom);
      draw(solid);
    }

    final w = visor.width, h = visor.height;
    final gaze = Offset(clock.gaze.dx * w * 0.035, clock.gaze.dy * h * 0.06);
    final eyeY = visor.top + h * 0.45;
    final dx = w * 0.19;

    // Eyes.
    if (mood == AssistantMood.happy) {
      final stroke = h * 0.075;
      for (final side in const [-1.0, 1.0]) {
        final c = Offset(visor.center.dx + side * dx, eyeY + h * 0.03) + gaze;
        final arc = Rect.fromCenter(center: c, width: w * 0.13, height: h * 0.26);
        shape((p) => canvas.drawArc(arc, math.pi * 1.08, math.pi * 0.84, false, _stroke(p, stroke)));
      }
    } else {
      final open = 1 - 0.92 * clock.blink;
      final wide = switch (mood) {
        AssistantMood.listening => 1.1,
        AssistantMood.thinking => 0.82,
        _ => 1.0,
      };
      final ew = w * 0.12;
      final eh = h * 0.36 * wide * open;
      final sparkle = Paint()..color = const Color(0xDDFFFFFF);
      for (final side in const [-1.0, 1.0]) {
        final c = Offset(visor.center.dx + side * dx, eyeY) + gaze;
        final rect = Rect.fromCenter(center: c, width: ew, height: math.max(eh, h * 0.035));
        shape((p) => canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(ew / 2)), p));
        // A small catch-light, only while the eye is open enough to hold it.
        if (open > 0.6 && mood != AssistantMood.thinking) {
          canvas.drawCircle(Offset(rect.left + ew * 0.32, rect.top + ew * 0.36), ew * 0.13, sparkle);
        }
      }
    }

    // Mouth.
    final mouth = Offset(visor.center.dx, visor.top + h * 0.77) + gaze * 0.4;
    switch (mood) {
      case AssistantMood.idle:
        final mw = w * 0.13;
        final path = Path()
          ..moveTo(mouth.dx - mw / 2, mouth.dy - h * 0.02)
          ..quadraticBezierTo(mouth.dx, mouth.dy + h * 0.07, mouth.dx + mw / 2, mouth.dy - h * 0.02);
        shape((p) => canvas.drawPath(path, _stroke(p, h * 0.05)));
      case AssistantMood.happy:
        final mw = w * 0.18;
        final path = Path()
          ..moveTo(mouth.dx - mw / 2, mouth.dy - h * 0.05)
          ..quadraticBezierTo(mouth.dx, mouth.dy + h * 0.16, mouth.dx + mw / 2, mouth.dy - h * 0.05)
          ..close();
        shape((p) => canvas.drawPath(path, p));
      case AssistantMood.speaking:
        final mw = w * (0.09 + 0.06 * l);
        final mh = h * (0.045 + 0.2 * l);
        final rect = Rect.fromCenter(center: mouth, width: mw, height: mh);
        shape((p) => canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(math.min(mw, mh) / 2)), p));
      case AssistantMood.listening:
        const bars = 7;
        final span = w * 0.24;
        final bw = span / (bars * 1.9);
        for (var i = 0; i < bars; i++) {
          final x = mouth.dx - span / 2 + (i + 0.5) * span / bars;
          final wave = 0.5 + 0.5 * math.sin(t * 9 + i * 1.3);
          final centre = 1 - (i - (bars - 1) / 2).abs() / bars;
          final bh = h * (0.035 + (0.05 + 0.2 * l) * wave * centre);
          final rect = Rect.fromCenter(center: Offset(x, mouth.dy), width: bw, height: bh);
          shape((p) => canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(bw / 2)), p));
        }
      case AssistantMood.thinking:
        for (var i = 0; i < 3; i++) {
          final phase = (t * 2.2 - i * 0.33) % 1.0;
          final lift = math.max(0.0, math.sin(phase * math.pi)) * h * 0.06;
          final c = Offset(mouth.dx + (i - 1) * w * 0.06, mouth.dy - lift);
          shape((p) => canvas.drawCircle(c, h * 0.035, p));
        }
    }
    canvas.restore();
  }

  static Paint _stroke(Paint base, double width) => Paint()
    ..color = base.color
    ..maskFilter = base.maskFilter
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  static Path _superellipse(Rect r, double n) {
    final path = Path();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final a = i / steps * 2 * math.pi;
      final c = math.cos(a), s = math.sin(a);
      final x = r.center.dx + r.width / 2 * c.sign * math.pow(c.abs(), 2 / n);
      final y = r.center.dy + r.height / 2 * s.sign * math.pow(s.abs(), 2 / n);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_AssistantPainter old) =>
      old.layers != layers || old.look != look || old.mood != mood || old.hud != hud;
}

/// Warms up the render layers for [look] (for example while onboarding shows the picker).
Future<void> precacheAssistant(AssistantLook look, double size, double devicePixelRatio) async {
  if (!look.isRobot) return;
  await _Layers.load(look, _AssetCache.bucket(size * devicePixelRatio));
}

/// Starts decoding [look]'s layers without waiting.
void warmAssistant(AssistantLook look, double size, double devicePixelRatio) =>
    unawaited(precacheAssistant(look, size, devicePixelRatio).catchError((Object _) {}));
