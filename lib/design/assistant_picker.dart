import 'package:flutter/material.dart';

import '../app/assistant.dart';
import 'assistant_avatar.dart';
import 'components.dart';
import 'tokens.dart';

/// A row of the five assistant looks. The chosen one smiles and gets a ring in its own colour.
class AssistantPicker extends StatelessWidget {
  const AssistantPicker({super.key, required this.selected, required this.onSelected, this.itemSize = 92});

  final AssistantKind selected;
  final ValueChanged<AssistantKind> onSelected;
  final double itemSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemSize + 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: AssistantLook.all.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.m),
        itemBuilder: (context, i) {
          final look = AssistantLook.all[i];
          final chosen = look.kind == selected;
          return Semantics(
            button: true,
            selected: chosen,
            label: '${look.name}, ${look.colour}',
            excludeSemantics: true,
            onTap: () => onSelected(look.kind),
            child: FocusRing(
              radius: Radii.card,
              child: InkWell(
                key: ValueKey('assistant-${look.kind.name}'),
                borderRadius: BorderRadius.circular(Radii.card),
                onTap: () => onSelected(look.kind),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: Motion.fade,
                      curve: Motion.standard,
                      width: itemSize,
                      height: itemSize,
                      decoration: BoxDecoration(
                        color: PrepColors.surface1,
                        borderRadius: BorderRadius.circular(Radii.card),
                        border: Border.all(
                          color: chosen ? look.glow : PrepColors.line,
                          width: chosen ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.card),
                        child: AssistantAvatar(
                          look: look,
                          size: itemSize,
                          mood: chosen ? AssistantMood.happy : AssistantMood.idle,
                          hud: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      look.name,
                      style: PrepType.label.copyWith(color: chosen ? PrepColors.text : PrepColors.text2),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
