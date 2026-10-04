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

  group('DayWindow', () {
    test('parseDayWindow : défaut si absent ou incohérent', () {
      expect(parseDayWindow(null), kDefaultDayWindow);
      expect(parseDayWindow({'startMin': 600}), kDefaultDayWindow);
      expect(parseDayWindow({'startMin': 600, 'endMin': 700}), kDefaultDayWindow); // < 4 h
      expect(parseDayWindow({'startMin': -10, 'endMin': 600}), kDefaultDayWindow);
      expect(parseDayWindow({'startMin': 0, 'endMin': 25 * 60}), kDefaultDayWindow);
    });
    test('parseDayWindow : valeurs valides, nombres ou chaînes', () {
      expect(parseDayWindow({'startMin': 240, 'endMin': 1200}), const DayWindow(240, 1200));
      expect(parseDayWindow({'startMin': '240', 'endMin': '1200'}), const DayWindow(240, 1200));
      expect(parseDayWindow({'startMin': 0, 'endMin': 24 * 60}), const DayWindow(0, 24 * 60));
    });
    test('label et toJson', () {
      expect(const DayWindow(240, 1200).label, '4 h → 20 h');
      expect(const DayWindow(270, 1230).label, '4 h 30 → 20 h 30');
      expect(const DayWindow(240, 1200).toJson(), {'startMin': 240, 'endMin': 1200});
    });
  });
}
