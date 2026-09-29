import 'package:flutter/material.dart';

import '../app/assistant.dart';
import 'assistant_avatar.dart';
import 'components.dart';
import 'tokens.dart';

/// The five assistant looks as a grid that always fits the width (three across on a phone), so no
/// card is ever cut off at the edge. The chosen one smiles and is outlined in its own colour.
class AssistantPicker extends StatelessWidget {
  const AssistantPicker({super.key, required this.selected, required this.onSelected, this.itemSize = 104});

  final AssistantKind selected;
  final ValueChanged<AssistantKind> onSelected;

  /// The largest a card may be; on a phone the width decides.
  final double itemSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = Space.m;
        final columns = constraints.maxWidth >= 560 ? 5 : 3;
        final width = ((constraints.maxWidth - gap * (columns - 1)) / columns).clamp(0.0, itemSize + 24);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final look in AssistantLook.all)
              SizedBox(
                width: width,
                child: _Choice(look: look, chosen: look.kind == selected, onTap: () => onSelected(look.kind)),
              ),
          ],
        );
      },
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.look, required this.chosen, required this.onTap});

  final AssistantLook look;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      label: '${look.name}, ${look.colour}',
      excludeSemantics: true,
      onTap: onTap,
      child: FocusRing(
        radius: Radii.card,
        child: Material(
          color: chosen ? Color.alphaBlend(look.glow.withValues(alpha: 0.10), PrepColors.surface1) : PrepColors.surface1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.card),
            side: BorderSide(color: chosen ? look.glow : PrepColors.line, width: chosen ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('assistant-${look.kind.name}'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.m),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(
                      builder: (context, box) => AssistantAvatar(
                        look: look,
                        size: box.maxWidth,
                        mood: chosen ? AssistantMood.happy : AssistantMood.idle,
                        hud: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    look.name,
                    style: PrepType.label.copyWith(color: chosen ? PrepColors.text : PrepColors.text2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
