import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';

/// Placeholder until the onboarding flow is built: finishes straight away.
class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        child: Center(
          child: PrimaryButton('Get started', onPressed: () async {
            await AppScope.of(context).assistant.finishOnboarding();
            onDone();
          }),
        ),
      ),
    );
  }
}
