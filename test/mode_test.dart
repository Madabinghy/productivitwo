import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/mode.dart';

void main() {
  MoodMark elan(DateTime at, int value) => MoodMark(at: at, ymd: '2026-10-27', kind: kMoodElan, value: value, moment: 'matin');

  test('modeOf : dernier élan de la journée vécue, sinon Normal ; seuils 2 / 3 / 4', () {
    final now = DateTime(2026, 10, 27, 15);
    expect(modeOf(const [], now, 300), DayMode.normal);
    expect(modeOf([elan(DateTime(2026, 10, 27, 8), 1)], now, 300), DayMode.low);
    expect(modeOf([elan(DateTime(2026, 10, 27, 8), 1), elan(DateTime(2026, 10, 27, 14), 5)], now, 300), DayMode.high);
    expect(modeOf([elan(DateTime(2026, 10, 27, 8), 3)], now, 300), DayMode.normal);
    // Une marque d'un autre jour vécu ne compte pas.
    final other = MoodMark(at: DateTime(2026, 10, 26, 20), ymd: '2026-10-26', kind: kMoodElan, value: 1);
    expect(modeOf([other], now, 300), DayMode.normal);
    expect(modeElanValue(DayMode.low), 2);
    expect(modeFromElan(modeElanValue(DayMode.high)), DayMode.high);
  });

  test('malgreTout / aFond : le mode en vigueur au moment du fait, pas le mode courant', () {
    final marks = [elan(DateTime(2026, 10, 27, 8), 1), elan(DateTime(2026, 10, 27, 14), 4)];
    expect(malgreTout(DateTime(2026, 10, 27, 10), marks, 300), isTrue);
    expect(malgreTout(DateTime(2026, 10, 27, 15), marks, 300), isFalse);
    expect(aFond(DateTime(2026, 10, 27, 15), marks, 300), isTrue);
    expect(aFond(DateTime(2026, 10, 27, 7), marks, 300), isFalse); // avant tout pointage : Normal
  });

  test('restDomains : parse, veille jusqu\'à la date incluse, budget 7 ou 14', () {
    final rest = parseRestDomains({'sante': '2026-10-31', 'maison': 'n/a', 'x': null});
    expect(rest, {'sante': '2026-10-31'});
    expect(isResting('sante', rest, DateTime(2026, 10, 31)), isTrue);
    expect(isResting('sante', rest, DateTime(2026, 11, 1)), isFalse);
    expect(isResting('maison', rest, DateTime(2026, 10, 27)), isFalse);
    expect(isResting(null, rest, DateTime(2026, 10, 27)), isFalse);
    expect(activeRests(rest, DateTime(2026, 11, 2)), isEmpty);
    expect(parseBudgetWindowDays(14), 14);
    expect(parseBudgetWindowDays('14'), 14);
    expect(parseBudgetWindowDays(10), 7);
    expect(parseBudgetWindowDays(null), 7);
  });
}
