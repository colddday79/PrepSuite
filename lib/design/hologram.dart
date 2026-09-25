import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'tokens.dart';

/// One looping, muted player for the Blender-rendered gold presence, shared by every screen so
/// route changes never re-decode the clip. Tests and previews turn it off with [enabled].
class HologramVideo with WidgetsBindingObserver {
  HologramVideo._();

  static final HologramVideo instance = HologramVideo._();
  static const asset = 'assets/video/presence_loop.mp4';

  /// The loop's first frame: shown until the video is ready, and instead of it under reduced motion.
  static const poster = 'assets/images/presence_poster.jpg';

  bool enabled = true;
  VideoPlayerController? _controller;
  final ValueNotifier<VideoPlayerController?> ready = ValueNotifier(null);

  Future<void> ensure() async {
    if (!enabled || _controller != null) return;
    final controller = VideoPlayerController.asset(
      asset,
      // Never take audio focus: the interviewer voice and the microphone own the audio session.
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      ready.value = controller;
      WidgetsBinding.instance.addObserver(this);
    } catch (error) {
      debugPrint('Presence video unavailable: $error');
      ready.value = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ready.value;
    if (controller == null) return;
    if (state == AppLifecycleState.resumed) {
      controller.play();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      controller.pause();
    }
  }
}

/// How far the warm light reaches past the presence box, as a fraction of its size.
const double _glowReach = 0.9;

/// The extra room above and below the presence box that the light spills into.
double presenceSpill(double size) => size * (_glowReach - 0.5);

/// Paints the presence and its light behind [child].
///
/// The clip is rendered on black, and Flutter cannot give a video texture its own blend mode, so
/// the stage is composed the other way round: a black base, the video on it, and then the room
/// (page colour plus the warm light) drawn over both with [BlendMode.screen]. Screen is
/// commutative, so this is exactly the video screened onto the room: the black drops out, the gold
/// lines add light, and at the stage edges the result is the plain page colour, with no seam.
///
/// [top] is where the presence box starts inside this widget. Content in [child] paints on top of
/// the stage, so a frosted panel placed there blurs the finished light.
class PresenceBackdrop extends StatelessWidget {
  const PresenceBackdrop({
    super.key,
    required this.top,
    required this.size,
    required this.child,
    this.level,
  });

  final double top;
  final double size;
  final ValueListenable<double>? level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spill = presenceSpill(size);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: top - spill,
          height: size + spill * 2,
          child: HologramStage(size: size, level: level),
        ),
        child,
      ],
    );
  }
}

class HologramStage extends StatelessWidget {
  const HologramStage({super.key, required this.size, this.level});

  final double size;
  final ValueListenable<double>? level;

  @override
  Widget build(BuildContext context) {
    final levels = level ?? const _Silent();
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: ValueListenableBuilder<double>(
          valueListenable: levels,
          builder: (context, value, _) {
            final l = value.clamp(0.0, 1.0);
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF000000)),
                // The box may be wider than the screen: only the black corners and the outer
                // ring run off the edges, clipped by this stage.
                OverflowBox(
                  minWidth: size,
                  maxWidth: size,
                  minHeight: size,
                  maxHeight: size,
                  child: Transform.scale(
                    scale: 1 + 0.05 * l,
                    child: SizedBox.square(dimension: size, child: const _PresenceVideo()),
                  ),
                ),
                CustomPaint(painter: _ScreenedRoom(size: size, level: l)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PresenceVideo extends StatelessWidget {
  const _PresenceVideo();

  @override
  Widget build(BuildContext context) {
    const poster = Image(
      image: AssetImage(HologramVideo.poster),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return poster;
    return ValueListenableBuilder<VideoPlayerController?>(
      valueListenable: HologramVideo.instance.ready,
      builder: (context, controller, _) {
        if (controller == null) return poster;
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        );
      },
    );
  }
}

/// The room drawn over the black base and the video with Screen blending.
class _ScreenedRoom extends CustomPainter {
  _ScreenedRoom({required this.size, required this.level});

  final double size;
  final double level;

  @override
  void paint(Canvas canvas, Size area) {
    final rect = Offset.zero & area;
    final center = rect.center;
    final radius = size * _glowReach;
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.screen);
    canvas.drawRect(rect, Paint()..color = PrepColors.bg);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            PrepColors.accent.withValues(alpha: 0.18 + 0.10 * level),
            PrepColors.accent.withValues(alpha: 0.06 + 0.03 * level),
            PrepColors.accent.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScreenedRoom old) => old.size != size || old.level != level;
}

class _Silent implements ValueListenable<double> {
  const _Silent();

  @override
  double get value => 0;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Mixes the interviewer's voice level and the microphone level into one smoothed value that
/// drives the presence pulse.
class LevelMix extends ValueNotifier<double> {
  LevelMix() : super(0);

  final List<StreamSubscription<double>> _subs = [];

  void listenTo(Stream<double> levels) {
    _subs.add(levels.listen((next) => value = value * 0.55 + next.clamp(0.0, 1.0) * 0.45));
  }

  void rest() => value = 0;

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
