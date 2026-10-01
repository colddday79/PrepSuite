import 'package:flutter/material.dart';

import '../app/assistant.dart';
import 'assistant_avatar.dart';
import 'components.dart';
import 'tokens.dart';

/// The five assistant looks in one row that always fits the width, so no card is cut off at the
/// edge and none is left alone on a second line. The chosen one smiles and is outlined.
class AssistantPicker extends StatelessWidget {
  const AssistantPicker({super.key, required this.selected, required this.onSelected});

  final AssistantKind selected;
  final ValueChanged<AssistantKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final look in AssistantLook.all) ...[
          if (look != AssistantLook.all.first) const SizedBox(width: Space.s),
          Expanded(child: _Choice(look: look, chosen: look.kind == selected, onTap: () => onSelected(look.kind))),
        ],
      ],
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
        radius: Radii.control,
        child: Material(
          color: chosen ? Color.alphaBlend(look.tone.withValues(alpha: 0.08), PrepColors.surface1) : PrepColors.surface1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
            side: BorderSide(color: chosen ? look.tone : PrepColors.line, width: chosen ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('assistant-${look.kind.name}'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.xs, Space.s),
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
                    style: PrepType.caption.copyWith(color: chosen ? PrepColors.text : PrepColors.text2),
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
