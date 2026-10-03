import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app/assistant.dart';
import 'hologram.dart';
import 'tokens.dart';

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
/// with the voice and the eyes blink and react. Behind it a quiet halo keeps a hint of the original
/// Jarvis feel, and under it a soft shadow and light pool stand it on a stage. The orb look shows
/// the gold hologram instead.
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
    this.stage = false,
    this.animate = true,
    this.semanticLabel,
  });

  /// Tests switch the per-frame animation off so fixed pumps stay deterministic.
  static bool live = true;

  final AssistantLook look;
  final double size;
  final AssistantMood mood;

  /// Voice level 0..1: the assistant's own voice while speaking, the microphone while listening.
  final ValueListenable<double>? level;

  /// Draw the halo behind the head and the stage (shadow, light pool, floor line) under the robot.
  final bool hud;

  /// Stand the robot on a pale disc of the coach's colour, so the white robot reads on the light
  /// page. Off where it already sits on a coloured card.
  final bool stage;

  /// Keep small picker and profile previews still while the main assistant moves.
  final bool animate;

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
    if (old.look != widget.look || old.size != widget.size || old.hud != widget.hud || old.animate != widget.animate) {
      _load();
    }

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

  bool get _animate =>
      widget.animate &&
      AssistantAvatar.live &&
      TickerMode.valuesOf(context).enabled &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

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
    if (_animate && !_ticker.isActive) {
      _clock.advance(null, widget.mood, widget.level?.value ?? 0);
    }
  }

  void _load() {
    final look = widget.look;
    if (!look.isRobot) return;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final px = _AssetCache.bucket(widget.size * ratio);
    // While a size animates, keep the sharpest layers already decoded for this look.
    if (look == _loaded &&
        px <= _bucket &&
        (!widget.hud || _layers?.shadow != null) &&
        (!widget.animate || _layers?.face != null)) {
      return;
    }
    _loaded = look;
    _bucket = px;
    final ticket = ++_requested;
    _Layers.load(look, px, hud: widget.hud, cacheFace: widget.animate).then((layers) {
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
          // A round black lens with the hologram inside, about as big as a robot looks in the same
          // box. The loop is rendered on black, so no blending is needed (a blended "room" leaks past
          // round clips on Android's renderer).
          child: Center(
            child: SizedBox.square(
              dimension: widget.size * 0.8,
              child: ClipOval(
                child: ColoredBox(
                  color: const Color(0xFF000000),
                  child: Padding(
                    padding: EdgeInsets.all(widget.size * 0.04),
                    child: _Pulse(
                      level: widget.level,
                      animate: widget.animate,
                      child: PresenceLoop(animate: widget.animate && AssistantAvatar.live),
                    ),
                  ),
                ),
              ),
            ),
          ),
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
              stage: widget.stage,
              pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Swells a little with the voice level.
class _Pulse extends StatelessWidget {
  const _Pulse({required this.level, required this.child, required this.animate});

  final ValueListenable<double>? level;
  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final level = this.level;
    if (level == null ||
        !animate ||
        !TickerMode.valuesOf(context).enabled ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return child;
    }
    return ValueListenableBuilder<double>(
      valueListenable: level,
      builder: (context, v, child) => Transform.scale(scale: 1 + 0.05 * v.clamp(0.0, 1.0), child: child),
      child: child,
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

  /// The halo's turn in radians. It drifts at rest and turns faster while thinking, easing between
  /// the two so the arcs never jump when the mood changes.
  double spin = 0;
  double _spinRate = _calmSpin;
  static const _calmSpin = 0.1;
  static const _busySpin = 0.5;

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
    _last = null;
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
      final rate = mood == AssistantMood.thinking ? _busySpin : _calmSpin;
      _spinRate += (rate - _spinRate) * math.min(1.0, dt * 2.5);
      spin += _spinRate * dt;
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
  const _Layers(this.body, this.glass, this.glow, this.shadow, this.face);

  final ui.Image body;
  final ui.Image glass;
  final ui.Image glow;
  final ui.Image? shadow;
  final _FaceTextures? face;

  static Future<_Layers> load(AssistantLook look, int px, {bool hud = true, bool cacheFace = true}) async {
    final images = await Future.wait([
      _AssetCache.image(look.bodyAsset, px),
      _AssetCache.image(look.glassAsset, px),
      _AssetCache.image(look.glowAsset, (px / 2).round()),
      if (hud) _ShadowCache.image(px),
    ]);
    final face = cacheFace ? await _FaceTextureCache.load(look, px) : null;
    return _Layers(images[0], images[1], images[2], hud ? images[3] : null, face);
  }
}

/// A feature's halo, bloom and core are static even while gaze moves it around the visor. Store
/// those passes in a small transparent texture so idle eyes and smiles do not blur every frame.
class _FaceTextures {
  const _FaceTextures(this.px, this.eyes, this.idleMouth, this.happyMouth, this.dot);

  final int px;
  final Map<AssistantMood, ui.Image> eyes;
  final ui.Image idleMouth;
  final ui.Image happyMouth;
  final ui.Image dot;
}

abstract final class _FaceTextureCache {
  static final Map<String, Future<_FaceTextures>> _faces = {};

  static Future<_FaceTextures> load(AssistantLook look, int px) {
    final key = '${look.kind.name}@$px';
    return _faces.putIfAbsent(key, () async {
      final w = (kAssistantVisor.width - 0.016) * px;
      final h = (kAssistantVisor.height - 0.016) * px;
      final edge = (h * 1.4).ceil();
      final center = Offset(edge / 2, edge / 2);
      final glow = look.glow;
      final core = Color.lerp(glow, const Color(0xFFFFFFFF), 0.28)!;

      Future<ui.Image> stamp(void Function(Canvas canvas, Paint paint) draw) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        draw(
          canvas,
          Paint()
            ..color = glow.withValues(alpha: 0.45)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.12),
        );
        draw(
          canvas,
          Paint()
            ..color = glow
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.035),
        );
        draw(canvas, Paint()..color = core);
        final picture = recorder.endRecording();
        try {
          return await picture.toImage(edge, edge);
        } finally {
          picture.dispose();
        }
      }

      Future<ui.Image> eye(double wide) => stamp((canvas, paint) {
        final ew = w * 0.12;
        final rect = Rect.fromCenter(center: center, width: ew, height: h * 0.36 * wide);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(ew / 2)), paint);
      });

      final idlePath = Path()
        ..moveTo(center.dx - w * 0.13 / 2, center.dy - h * 0.02)
        ..quadraticBezierTo(center.dx, center.dy + h * 0.07, center.dx + w * 0.13 / 2, center.dy - h * 0.02);
      final happyPath = Path()
        ..moveTo(center.dx - w * 0.18 / 2, center.dy - h * 0.05)
        ..quadraticBezierTo(center.dx, center.dy + h * 0.16, center.dx + w * 0.18 / 2, center.dy - h * 0.05)
        ..close();
      try {
        final images = await Future.wait([
          eye(1),
          eye(1.1),
          eye(0.82),
          stamp(
            (canvas, paint) => canvas.drawArc(
              Rect.fromCenter(center: center, width: w * 0.13, height: h * 0.26),
              math.pi * 1.08,
              math.pi * 0.84,
              false,
              _AssistantPainter._stroke(paint, h * 0.075),
            ),
          ),
          stamp((canvas, paint) => canvas.drawPath(idlePath, _AssistantPainter._stroke(paint, h * 0.05))),
          stamp((canvas, paint) => canvas.drawPath(happyPath, paint)),
          stamp((canvas, paint) => canvas.drawCircle(center, h * 0.035, paint)),
        ]);
        return _FaceTextures(
          px,
          {
            AssistantMood.idle: images[0],
            AssistantMood.speaking: images[0],
            AssistantMood.listening: images[1],
            AssistantMood.thinking: images[2],
            AssistantMood.happy: images[3],
          },
          images[4],
          images[5],
          images[6],
        );
      } catch (_) {
        _faces.remove(key);
        rethrow;
      }
    });
  }
}

/// The contact shadow keeps its soft Gaussian edges, but its blur is rasterized only once per
/// display-size bucket. Every robot shares the same small transparent texture.
abstract final class _ShadowCache {
  static final Map<int, Future<ui.Image>> _images = {};
  static const width = 0.5;
  static const height = 0.18;
  static const darkness = 1.08;

  static Future<ui.Image> image(int px) => _images.putIfAbsent(px, () async {
    final w = (px * width).ceil();
    final h = (px * height).ceil();
    final center = Offset(w / 2, h / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: px * 0.34, height: px * 0.05),
      Paint()
        ..color = const Color.fromRGBO(0, 0, 0, 0.3 * darkness)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, px * 0.018),
    );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: px * 0.17, height: px * 0.022),
      Paint()
        ..color = const Color.fromRGBO(0, 0, 0, 0.24 * darkness)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, px * 0.007),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(w, h);
    } catch (_) {
      _images.remove(px);
      rethrow;
    } finally {
      picture.dispose();
    }
  });
}

/// Decoded render layers, shared between avatars and decoded at about the size they are shown.
abstract final class _AssetCache {
  static final Map<String, Future<ui.Image>> _images = {};

  /// Decode sizes step in 192 px so a handful of sizes share one decode, up to the 1536 px renders.
  static int bucket(double px) => (((px / 192).ceil()) * 192).clamp(192, 1536);

  static Future<ui.Image> image(String asset, int px) {
    final key = '$asset@$px';
    return _images.putIfAbsent(key, () async {
      try {
        final buffer = await rootBundle.loadBuffer(asset);
        // Never upscale while decoding: a smaller file stays at its own size and the GPU scales it.
        final codec = await ui.instantiateImageCodecWithSize(
          buffer,
          getTargetSize: (w, h) => ui.TargetImageSize(width: math.min(px, w), height: math.min(px, h)),
        );
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } catch (_) {
        // An unavailable asset can be retried when a later screen requests it.
        _images.remove(key);
        rethrow;
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

class _AssistantPainter extends CustomPainter {
  _AssistantPainter({
    required this.layers,
    required this.look,
    required this.mood,
    required this.clock,
    required this.hud,
    required this.stage,
    required this.pixelRatio,
  }) : super(repaint: clock);

  // Stage anchors as fractions of the render square, matched to the Blender camera.
  /// The floor line under the robot, where the contact shadow sits.
  static const double _floorY = 0.925;

  /// Seconds per hover cycle, and how far the robot rises and sinks, as a fraction of the square.
  static const double _hoverPeriod = 4.2;
  static const double _hoverTravel = 0.012;

  final _Layers? layers;
  final AssistantLook look;
  final AssistantMood mood;
  final _FaceClock clock;
  final bool hud;
  final bool stage;
  final double pixelRatio;

  /// -1 at the top of the hover, 1 at the bottom (closest to the floor).
  double get _hover => math.sin(clock.t * 2 * math.pi / _hoverPeriod);

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
    if (stage) {
      canvas.drawCircle(Offset(s * 0.5, s * 0.5), s * 0.47, Paint()..color = look.soft);
    }
    if (hud) _paintHud(canvas, s);

    final layers = this.layers;
    if (layers == null) return;

    // A slow hover and the smallest sway, so the robot never looks frozen.
    final float = _hover * s * _hoverTravel;
    final sway = math.sin(t * 2 * math.pi / 6.8) * 0.012;
    canvas.save();
    canvas.translate(s / 2, s / 2 + float);
    canvas.rotate(sway);
    canvas.translate(-s / 2, -s / 2);

    final box = Offset.zero & size;
    // Mipmapped sampling keeps moving edges steady without bicubic work over each full image.
    final smoothing = Paint()..filterQuality = FilterQuality.medium;
    _drawImage(canvas, layers.body, box, smoothing);
    _paintFace(canvas, s);
    // Light layers carry their own transparency (baked from renders on black), so they are
    // drawn normally: they add light and leave the page untouched everywhere else.
    _drawImage(canvas, layers.glass, box, smoothing);
    _drawImage(
      canvas,
      layers.glow,
      box,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, _energy.clamp(0.0, 1.0)),
    );
    canvas.restore();
  }

  void _drawImage(Canvas canvas, ui.Image image, Rect dst, Paint paint) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, paint);
  }

  // The robot stands on a lit floor, like a lamp in a product shot: a warm pool of the theme
  // accent spread flat under it, then a soft contact shadow. No halo, rings or glows around it.
  void _paintHud(Canvas canvas, double s) {
    final floor = Offset(s * 0.5, s * _floorY);

    final pool = s * 0.34;
    canvas.save();
    canvas.translate(floor.dx, floor.dy);
    canvas.scale(1, 0.2);
    canvas.drawCircle(
      Offset.zero,
      pool,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, pool, [
          PrepColors.accent.withValues(alpha: 0.24),
          PrepColors.accent.withValues(alpha: 0.07),
          PrepColors.accent.withValues(alpha: 0),
        ], const [0, 0.5, 1]),
    );
    canvas.restore();

    // A soft contact shadow (a wide penumbra and a tight core), a little tighter and darker as the
    // hover brings the robot down. Only once the robot is there to cast it.
    final shadow = layers?.shadow;
    if (shadow != null) {
      final near = _hover;
      final spread = 1 - 0.06 * near;
      final dark = 1 + 0.08 * near;
      _drawImage(
        canvas,
        shadow,
        Rect.fromCenter(
          center: floor,
          width: s * _ShadowCache.width * spread,
          height: s * _ShadowCache.height * spread,
        ),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, dark / _ShadowCache.darkness),
      );
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

    final face = layers?.face;
    void stamp(ui.Image image, Offset center) {
      final scale = s / face!.px;
      _drawImage(
        canvas,
        image,
        Rect.fromCenter(center: center, width: image.width * scale, height: image.height * scale),
        Paint()..filterQuality = FilterQuality.medium,
      );
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
        if (face != null) {
          stamp(face.eyes[mood]!, c);
        } else {
          final arc = Rect.fromCenter(center: c, width: w * 0.13, height: h * 0.26);
          shape((p) => canvas.drawArc(arc, math.pi * 1.08, math.pi * 0.84, false, _stroke(p, stroke)));
        }
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
        if (face != null && clock.blink == 0) {
          stamp(face.eyes[mood]!, c);
        } else {
          shape((p) => canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(ew / 2)), p));
        }
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
        if (face != null) {
          stamp(face.idleMouth, mouth);
        } else {
          final mw = w * 0.13;
          final path = Path()
            ..moveTo(mouth.dx - mw / 2, mouth.dy - h * 0.02)
            ..quadraticBezierTo(mouth.dx, mouth.dy + h * 0.07, mouth.dx + mw / 2, mouth.dy - h * 0.02);
          shape((p) => canvas.drawPath(path, _stroke(p, h * 0.05)));
        }
      case AssistantMood.happy:
        if (face != null) {
          stamp(face.happyMouth, mouth);
        } else {
          final mw = w * 0.18;
          final path = Path()
            ..moveTo(mouth.dx - mw / 2, mouth.dy - h * 0.05)
            ..quadraticBezierTo(mouth.dx, mouth.dy + h * 0.16, mouth.dx + mw / 2, mouth.dy - h * 0.05)
            ..close();
          shape((p) => canvas.drawPath(path, p));
        }
      case AssistantMood.speaking:
        final mw = w * (0.09 + 0.06 * l);
        final mh = h * (0.045 + 0.2 * l);
        final rect = Rect.fromCenter(center: mouth, width: mw, height: mh);
        shape((p) => canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(math.min(mw, mh) / 2)), p));
      case AssistantMood.listening:
        const bars = 7;
        final span = w * 0.24;
        final bw = span / (bars * 1.9);
        final wavePath = Path();
        for (var i = 0; i < bars; i++) {
          final x = mouth.dx - span / 2 + (i + 0.5) * span / bars;
          final wave = 0.5 + 0.5 * math.sin(t * 9 + i * 1.3);
          final centre = 1 - (i - (bars - 1) / 2).abs() / bars;
          final bh = h * (0.035 + (0.05 + 0.2 * l) * wave * centre);
          final rect = Rect.fromCenter(center: Offset(x, mouth.dy), width: bw, height: bh);
          wavePath.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(bw / 2)));
        }
        shape((p) => canvas.drawPath(wavePath, p));
      case AssistantMood.thinking:
        for (var i = 0; i < 3; i++) {
          final phase = (t * 2.2 - i * 0.33) % 1.0;
          final lift = math.max(0.0, math.sin(phase * math.pi)) * h * 0.06;
          final c = Offset(mouth.dx + (i - 1) * w * 0.06, mouth.dy - lift);
          if (face != null) {
            stamp(face.dot, c);
          } else {
            shape((p) => canvas.drawCircle(c, h * 0.035, p));
          }
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
      old.layers != layers || old.look != look || old.mood != mood || old.hud != hud || old.stage != stage || old.pixelRatio != pixelRatio;
}

/// Warms up the render layers for [look] (for example while onboarding shows the picker).
Future<void> precacheAssistant(AssistantLook look, double size, double devicePixelRatio) async {
  if (!look.isRobot) return;
  await _Layers.load(look, _AssetCache.bucket(size * devicePixelRatio));
}

/// Starts decoding [look]'s layers without waiting.
void warmAssistant(AssistantLook look, double size, double devicePixelRatio) =>
    unawaited(precacheAssistant(look, size, devicePixelRatio).catchError((Object _) {}));
