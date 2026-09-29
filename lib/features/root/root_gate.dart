import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design/assistant_avatar.dart';
import '../../design/tokens.dart';
import '../onboarding/onboarding_flow.dart';
import '../shell/app_shell.dart';

/// Decides what the person sees first: a calm splash while saved choices are still being read,
/// first-run onboarding, or the app itself. Listens to [AppServices.assistant], so finishing (or
/// resetting, from Profile's "See the introduction again") switches straight over.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final assistant = AppScope.of(context).assistant;
    return ListenableBuilder(
      listenable: assistant,
      builder: (context, _) {
        if (!assistant.restored) return const _Splash();
        if (!assistant.onboarded) return OnboardingFlow(onDone: () {});
        return const AppShell();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final look = AppScope.of(context).assistant.value;
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: Center(
        child: AssistantAvatar(look: look, size: 180, mood: AssistantMood.idle, semanticLabel: 'Loading PrepSuite'),
      ),
    );
  }
}
