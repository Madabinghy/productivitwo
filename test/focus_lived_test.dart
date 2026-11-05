import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';

void main() {
  tearDown(() => focusDayStartMin = 300);

  test('jour visé : avant la bascule, aujourd\'hui reste la veille', () {
    focusDayStartMin = 300; // 5 h
    expect(focusToday(DateTime(2026, 11, 6, 1, 0)), DateTime(2026, 11, 5));
    expect(focusToday(DateTime(2026, 11, 6, 5, 0)), DateTime(2026, 11, 6));
    expect(focusToday(DateTime(2026, 11, 6, 23, 59)), DateTime(2026, 11, 6));
    focusDayStartMin = 0; // bascule à minuit
    expect(focusToday(DateTime(2026, 11, 6, 1, 0)), DateTime(2026, 11, 6));
  });
}
