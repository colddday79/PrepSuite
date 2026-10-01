import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/assistant.dart';
import 'package:prepsuite/design/tokens.dart';

import 'design_test.dart' show contrast;

void main() {
  test('every coach colour carries dark button text at 7:1 and reads on the page', () {
    for (final look in AssistantLook.all) {
      expect(contrast(PrepColors.bg, look.tone), greaterThanOrEqualTo(7), reason: look.name);
      expect(contrast(look.tone, PrepColors.surface2), greaterThanOrEqualTo(4.5), reason: look.name);
    }
  });

  test('no two coaches share a colour family', () {
    double hue(AssistantLook look) => HSLColor.fromColor(look.tone).hue;
    final looks = AssistantLook.all;
    for (var i = 0; i < looks.length; i++) {
      for (var j = i + 1; j < looks.length; j++) {
        final d = (hue(looks[i]) - hue(looks[j])).abs();
        expect(d > 180 ? 360 - d : d, greaterThanOrEqualTo(15), reason: '${looks[i].name} and ${looks[j].name}');
      }
    }
  });
}
