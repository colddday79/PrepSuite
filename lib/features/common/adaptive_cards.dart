import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// Keeps cards side by side when their text has room, otherwise gives each a full row.
class AdaptiveCardRow extends StatelessWidget {
  const AdaptiveCardRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final columns = box.maxWidth >= 280 * scale + Space.m ? 2 : 1;
        final width = (box.maxWidth - Space.m * (columns - 1)) / columns;
        return Wrap(
          spacing: Space.m,
          runSpacing: Space.m,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}
