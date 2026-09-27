import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';

void main() {
  test('défauts : 7 h lun→ven, 0 le week-end', () {
    final cap = defaultWeekCapacity();
    expect(cap['mon'], 420);
    expect(cap['fri'], 420);
    expect(cap['sat'], 0);
    expect(cap['sun'], 0);
    expect(cap.keys.toList(), kWeekDayKeys);
  });

  test('parse : null / type inattendu → défauts', () {
    expect(parseWeekCapacity(null), defaultWeekCapacity());
    expect(parseWeekCapacity('x'), defaultWeekCapacity());
  });

  test('parse : fusion partielle, clés inconnues et négatifs ignorés', () {
    final cap = parseWeekCapacity({
      'mon': 300,
      'sat': 120.0,
      'sun': -5,
      'lundi': 999,
      'tue': 'abc',
    });
    expect(cap['mon'], 300);
    expect(cap['tue'], 420);
    expect(cap['sat'], 120);
    expect(cap['sun'], 0);
    expect(cap.containsKey('lundi'), isFalse);
  });

  test('capacité d\'une date via sa clé de jour', () {
    final cap = parseWeekCapacity({'wed': 60});
    expect(weekDayKey(DateTime(2026, 9, 28)), 'mon'); // lundi
    expect(weekDayKey(DateTime(2026, 10, 4)), 'sun');
    expect(capacityMinFor(cap, DateTime(2026, 9, 30)), 60); // mercredi
    expect(capacityMinFor(cap, DateTime(2026, 10, 3)), 0); // samedi
  });
}
