import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/web/duration_chooser.dart';

void main() {
  test('durationStepUp / Down : 5 min sous l\'heure, 15 au-delà, plancher', () {
    expect(durationStepUp(null), 15);
    expect(durationStepUp(30), 35);
    expect(durationStepUp(60), 75);
    expect(durationStepDown(75), 60);
    expect(durationStepDown(60), 55);
    expect(durationStepDown(5), isNull);
    expect(durationStepDown(null), isNull);
  });
}
