import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';

/// Plain-words explanation of what happens to the person's voice. Returns true on Accept.
/// With [infoOnly] it is a read-again view with a single Close action.
Future<bool> showConsentSheet(BuildContext context, {bool infoOnly = false}) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PrepColors.surface1,
    barrierColor: PrepColors.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    builder: (context) => _ConsentSheet(infoOnly: infoOnly),
  );
  return accepted ?? false;
}

class _ConsentSheet extends StatelessWidget {
  const _ConsentSheet({required this.infoOnly});

  final bool infoOnly;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xxl, Space.x3, Space.xxl, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: HeadingScale(child: Text(infoOnly ? 'How your voice is used' : 'Before you start', style: PrepType.headline)),
          ),
          const SizedBox(height: Space.xxl),
          const _Point(
            icon: PrepIcons.mic,
            text: 'Your voice becomes text on this phone.',
          ),
          const _Point(
            icon: PrepIcons.arrowUpRight,
            text: 'Only that text and your pace go to the AI coach, which may run in the cloud.',
          ),
          const _Point(
            icon: PrepIcons.lock,
            text: 'Audio is never uploaded, and recordings are deleted after use.',
          ),
          const SizedBox(height: Space.l),
          if (infoOnly)
            PrimaryButton('Close', onPressed: () => Navigator.of(context).pop(false))
          else ...[
            PrimaryButton('Accept', onPressed: () => Navigator.of(context).pop(true)),
            const SizedBox(height: Space.s),
            Center(child: QuietButton('Not now', onPressed: () => Navigator.of(context).pop(false))),
          ],
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final PrepIcons icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: PrepIcon(icon, color: PrepColors.accent, size: 22)),
          const SizedBox(width: Space.l),
          Expanded(child: Text(text, style: PrepType.bodyL)),
        ],
      ),
    );
  }
}
