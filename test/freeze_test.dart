import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/rest_periods.dart';

void main() {
  test('gel d\'une activité : à l\'avance, dégel, jours gelés', () {
    var f = withFreezeSet(const [], 'a', '2026-11-02', '2026-12-20', '2027-01-03');
    expect(currentFreezeOf(f, 'a', '2026-11-02')?.from, '2026-12-20');
    expect(frozenDaysOfActivity('a', f, '2026-11-02'), isEmpty);
    expect(frozenDaysOfActivity('a', f, '2026-12-21'), {'2026-12-20', '2026-12-21'});
    f = withFreezeSet(f, 'a', '2026-11-02', '2026-11-01', '2026-11-08');
    expect(f.length, 1);
    expect(f.single.from, '2026-11-02');
    f = withFreezeLifted(f, 'a', '2026-11-04');
    expect(f.single.to, '2026-11-03');
    expect(currentFreezeOf(f, 'a', '2026-11-04'), isNull);
  });
}
