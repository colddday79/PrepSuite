import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite/app/assistant.dart';
import 'package:prepsuite/design/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_test.dart' show contrast;

void main() {
  test('every coach colour reads on the light page, on its own stage and under light text', () {
    for (final look in AssistantLook.all) {
      expect(contrast(look.tone, PrepColors.bg), greaterThanOrEqualTo(4.5), reason: look.name);
      expect(contrast(look.tone, PrepColors.surface2), greaterThanOrEqualTo(4.5), reason: look.name);
      expect(contrast(look.tone, look.soft), greaterThanOrEqualTo(4.5), reason: look.name);
      expect(contrast(PrepColors.bg, look.tone), greaterThanOrEqualTo(4.5), reason: look.name);
      expect(contrast(PrepColors.text, look.soft), greaterThanOrEqualTo(7), reason: look.name);
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

  test('a saved choice of a retired look opens as the default', () async {
    for (final retired in ['orb', 'onyx']) {
      SharedPreferences.setMockInitialValues({'assistant.kind.v1': retired, 'onboarding.done.v1': true});
      final store = AssistantStore(persist: true);
      await store.restore();
      expect(store.value.kind, AssistantKind.nova, reason: retired);
      expect(store.onboarded, isTrue);
    }
  });
}
