import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// Placeholder until "Talk to your assistant" is built.
class TalkScreen extends StatelessWidget {
  const TalkScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(backgroundColor: PrepColors.bg, body: Center(child: Text('Talk', style: PrepType.headline)));
}
