import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/assistant.dart';
import 'assistant_avatar.dart';
import 'components.dart';
import 'glass.dart';
import 'tokens.dart';

/// The four coaches as round metal discs, each holding its robot's head and shoulders. The chosen
/// one smiles inside a thin accent ring. [showNames] puts each name under its disc (Profile); the
/// onboarding stage already names the chosen coach, so it hides them. The discs wrap onto more
/// rows on narrow screens or with larger text.
class AssistantPicker extends StatelessWidget {
  const AssistantPicker({super.key, required this.selected, required this.onSelected, this.showNames = true});

  final AssistantKind selected;
  final ValueChanged<AssistantKind> onSelected;
  final bool showNames;

  /// The whole choice, ring included: 64 dp.
  static const double disc = 64;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
        final item = showNames ? math.max(disc, 60 * scale) : disc;
        final count = AssistantLook.all.length;
        final gap = ((box.maxWidth - item * count) / (count - 1)).clamp(Space.s, Space.xl);
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: Space.m,
          children: [
            for (final look in AssistantLook.all)
              SizedBox(
                width: item,
                child: _Choice(
                  look: look,
                  chosen: look.kind == selected,
                  showName: showNames,
                  onTap: () => onSelected(look.kind),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.look, required this.chosen, required this.showName, required this.onTap});

  final AssistantLook look;
  final bool chosen;
  final bool showName;
  final VoidCallback onTap;

  static const double _ring = 2;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    const outer = AssistantPicker.disc;
    const inner = outer - (_ring + _gap) * 2;
    // The robot is drawn larger than the disc and cropped to its head and shoulders, so the face
    // (the one part that differs between coaches) fills the circle.
    const robot = inner * 1.85;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final portrait = ClipOval(
      child: SizedBox.square(
        dimension: inner,
        child: CustomPaint(
          painter: _DiscPainter(top: PrepColors.surface2, bottom: PrepColors.metalBottom, rim: PrepColors.rimLight),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: (inner - robot) / 2,
                top: inner * 0.5 - robot * 0.33,
                width: robot,
                height: robot,
                child: AssistantAvatar(
                  look: look,
                  size: robot,
                  mood: chosen ? AssistantMood.happy : AssistantMood.idle,
                  hud: false,
                  animate: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: chosen,
      label: '${look.name}, ${look.colour}',
      excludeSemantics: true,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusRing(
            radius: outer / 2,
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('assistant-${look.kind.name}'),
                onTap: onTap,
                customBorder: const CircleBorder(),
                focusColor: Colors.transparent,
                child: SizedBox.square(
                  dimension: outer,
                  child: AnimatedContainer(
                    duration: still ? Duration.zero : Motion.fade,
                    curve: Motion.standard,
                    decoration: ShapeDecoration(
                      shape: CircleBorder(
                        side: BorderSide(
                          color: chosen ? PrepColors.accentDeep : const Color(0x00000000),
                          width: _ring,
                        ),
                      ),
                    ),
                    child: Center(child: portrait),
                  ),
                ),
              ),
            ),
          ),
          if (showName) ...[
            const SizedBox(height: Space.xs),
            Text(
              look.name,
              textAlign: TextAlign.center,
              style: PrepType.meta.copyWith(color: chosen ? PrepColors.text : PrepColors.text2),
            ),
          ],
        ],
      ),
    );
  }
}

/// Round smoked glass, like the cards (lib/design/glass.dart).
class _DiscPainter extends CustomPainter {
  _DiscPainter({required this.top, required this.bottom, required this.rim});

  final Color top;
  final Color bottom;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    paintGlass(canvas, RRect.fromRectAndRadius(rect, Radius.circular(size.shortestSide / 2)), top: top, bottom: bottom);
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.top != top || old.bottom != bottom || old.rim != rim;
}
