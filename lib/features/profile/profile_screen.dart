import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// Placeholder until the profile screen is built.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(child: Center(child: Text('Profile', style: PrepType.headline))),
    );
  }
}
