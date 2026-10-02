import 'package:flutter/material.dart';

import '../app/assistant.dart';
import 'assistant_avatar.dart';
import 'components.dart';
import 'tokens.dart';

/// The looks share one row when their names fit, and wrap on narrow screens or with larger text.
/// The chosen one smiles and is outlined.
class AssistantPicker extends StatelessWidget {
  const AssistantPicker({super.key, required this.selected, required this.onSelected});

  final AssistantKind selected;
  final ValueChanged<AssistantKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final columns = ((box.maxWidth + Space.s) / (56 * scale + Space.s)).floor().clamp(1, AssistantLook.all.length);
        final width = (box.maxWidth - Space.s * (columns - 1)) / columns;
        return Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
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
        radius: Radii.control,
        child: Material(
          color: chosen
              ? Color.alphaBlend(look.tone.withValues(alpha: 0.08), PrepColors.surface1)
              : PrepColors.surface1,
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
                  LayoutBuilder(
                    builder: (context, box) => Center(
                      child: AssistantAvatar(
                        look: look,
                        size: box.maxWidth.clamp(0.0, 72.0),
                        mood: chosen ? AssistantMood.happy : AssistantMood.idle,
                        hud: false,
                        animate: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    look.name,
                    style: PrepType.caption.copyWith(color: chosen ? PrepColors.text : PrepColors.text2),
                    textAlign: TextAlign.center,
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
