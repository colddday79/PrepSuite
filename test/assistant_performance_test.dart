import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/assistant.dart';
import 'package:prepsuite/design/assistant_avatar.dart';
import 'package:prepsuite/design/hologram.dart';
// The video player's platform interface supplies the native-player test fake.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

Widget _host(Widget child, {bool active = true, bool reducedMotion = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reducedMotion),
  child: TickerMode(
    enabled: active,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  ),
);

void main() {
  testWidgets('every coach render and cached face decodes at phone resolution', (tester) async {
    await tester.runAsync(() => Future.wait([
      for (final look in AssistantLook.all) precacheAssistant(look, 96, 3),
    ]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('static assistant previews stop scheduling animation frames', (tester) async {
    AssistantAvatar.live = true;
    await tester.runAsync(() => precacheAssistant(AssistantLook.nova, 96, 1));
    await tester.pumpWidget(_host(const AssistantAvatar(look: AssistantLook.nova, size: 96, animate: false)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host(const AssistantAvatar(look: AssistantLook.nova, size: 96)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1, reason: 'the main assistant still animates');

    await tester.pumpWidget(_host(const AssistantAvatar(look: AssistantLook.nova, size: 96, animate: false)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('hidden routes and reduced motion stop robot frame callbacks', (tester) async {
    AssistantAvatar.live = true;
    await tester.runAsync(() => precacheAssistant(AssistantLook.nova, 96, 1));
    final level = ValueNotifier<double>(0);
    addTearDown(level.dispose);
    final avatar = AssistantAvatar(look: AssistantLook.nova, size: 96, level: level);
    await tester.pumpWidget(_host(avatar));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);

    await tester.pumpWidget(_host(avatar, active: false));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    level.value = 0.7;
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'hidden voice levels do not repaint the robot');

    await tester.pumpWidget(_host(avatar, reducedMotion: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    level.value = 0.9;
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'reduced motion also suppresses voice repaint pulses');

    await tester.pumpWidget(_host(avatar));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('orb decodes on demand and pauses without visible animated consumers', (tester) async {
    final original = VideoPlayerPlatform.instance;
    final platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    final video = HologramVideo.instance..enabled = true;
    addTearDown(() {
      final controller = video.ready.value;
      if (controller != null) unawaited(controller.dispose());
      video.ready.value = null;
      VideoPlayerPlatform.instance = original;
      unawaited(platform.events.close());
    });

    Widget loops({int count = 1, bool active = true, bool reducedMotion = false, bool animate = true}) => _host(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            SizedBox.square(
              dimension: 96,
              child: PresenceLoop(key: ValueKey(i), animate: animate),
            ),
        ],
      ),
      active: active,
      reducedMotion: reducedMotion,
    );

    await video.ensure();
    await tester.pumpWidget(loops(animate: false));
    await tester.pumpWidget(loops(reducedMotion: true));
    await tester.pumpWidget(loops(active: false));
    expect(platform.creates, 0, reason: 'startup and static posters do not create a decoder');

    await tester.pumpWidget(loops());
    await tester.pump();
    await tester.pump();
    expect(platform.creates, 1);
    expect(video.ready.value?.value.isPlaying, isTrue);
    expect(platform.playing, isTrue);

    await tester.pumpWidget(loops(count: 2));
    await tester.pumpWidget(loops(count: 1));
    expect(platform.creates, 1, reason: 'visible orb widgets share a decoder');
    expect(video.ready.value?.value.isPlaying, isTrue);

    await tester.pumpWidget(loops(active: false));
    await tester.pump();
    expect(video.ready.value?.value.isPlaying, isFalse);
    expect(platform.playing, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(video.ready.value?.value.isPlaying, isFalse, reason: 'app resume does not play a hidden orb');

    await tester.pumpWidget(loops());
    await tester.pump();
    expect(video.ready.value?.value.isPlaying, isTrue);
    expect(platform.creates, 1, reason: 'returning to the orb reuses its paused decoder');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(video.ready.value?.value.isPlaying, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(video.ready.value?.value.isPlaying, isTrue);

    await tester.pumpWidget(loops(reducedMotion: true));
    await tester.pump();
    expect(video.ready.value?.value.isPlaying, isFalse);

    platform.playGate = Completer<void>();
    await tester.pumpWidget(loops());
    await tester.pump();
    await tester.pumpWidget(loops(active: false));
    await tester.pump();
    platform.playGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(platform.playing, isFalse, reason: 'a delayed native play cannot outlive its visible route');
    expect(video.ready.value?.value.isPlaying, isFalse);
    platform.playGate = null;

    await tester.pumpWidget(_host(const SizedBox.square(dimension: 200, child: HologramStage(size: 160))));
    await tester.pump();
    expect(platform.playing, isTrue, reason: 'a standalone stage also acquires shared playback');
    expect(platform.creates, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(video.ready.value?.value.isPlaying, isFalse, reason: 'leaving the last orb releases playback');
    expect(platform.playing, isFalse);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => video.ready.value!.dispose());
    expect(platform.disposals, 1);
    video.ready.value = null;
  });
}

class _VideoPlatform extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>();
  int creates = 0;
  int disposals = 0;
  bool playing = false;
  Completer<void>? playGate;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    creates++;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(128, 128),
        duration: const Duration(seconds: 2),
      ),
    );
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposals++;
  }

  @override
  Future<void> play(int playerId) async {
    await playGate?.future;
    playing = true;
  }

  @override
  Future<void> pause(int playerId) async {
    playing = false;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.expand();
}
