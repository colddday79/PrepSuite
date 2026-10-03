import 'package:flutter/widgets.dart';

import '../../design/icons.dart';
import '../../design/tokens.dart';

/// The person's initial on a raised metal disc (a person glyph until they give a name), with an
/// optional 1.5 dp [ring]. Decorative: wrap it in a control that says what it does.
class InitialDisc extends StatelessWidget {
  const InitialDisc({super.key, required this.name, this.size = 40, this.ring});

  final String name;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? null : name.trim().characters.first.toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: PrepColors.surface2,
          border: ring == null ? Border.all(color: PrepColors.rimLight) : Border.all(color: ring!, width: 1.5),
        ),
        alignment: Alignment.center,
        child: initial == null
            ? PrepIcon(PrepIcons.user, color: PrepColors.text2, size: size * 0.5)
            : Text(
                initial,
                textScaler: TextScaler.noScaling,
                style: PrepType.titleM.copyWith(fontSize: size * 0.42, height: 1),
              ),
      ),
    );
  }
}
