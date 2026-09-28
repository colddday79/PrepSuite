import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/assistant.dart';
import '../design/assistant_avatar.dart';
import '../design/tokens.dart';

/// Developer preview of the assistant in every mood:
/// flutter run -t lib/dev/assistant_preview.dart
void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Preview()));

class _Preview extends StatefulWidget {
  const _Preview();

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final _level = ValueNotifier<double>(0);
  late final Timer _timer;
  var _look = 0;
  var _mood = AssistantMood.speaking;

  @override
  void initState() {
    super.initState();
    var t = 0.0;
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      t += 0.06;
      final syllables = (math.sin(t * 13) * 0.5 + 0.5) * (math.sin(t * 2.1) * 0.35 + 0.65);
      _level.value = syllables.clamp(0.0, 1.0);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = AssistantLook.all[_look];
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Center(child: AssistantAvatar(look: look, size: 360, mood: _mood, level: _level)),
            Wrap(
              spacing: 8,
              children: [
                for (final m in AssistantMood.values)
                  TextButton(onPressed: () => setState(() => _mood = m), child: Text(m.name)),
              ],
            ),
            TextButton(
              onPressed: () => setState(() => _look = (_look + 1) % AssistantLook.all.length),
              child: Text('Next look (${look.name})'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final l in AssistantLook.all.take(4))
                  AssistantAvatar(look: l, size: 96, mood: AssistantMood.happy, hud: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
