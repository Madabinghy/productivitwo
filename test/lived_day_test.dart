import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';

void main() {
  test('livedDate / livedYmd : avant la bascule = la veille', () {
    expect(livedDate(DateTime(2026, 10, 17, 0, 30), 5 * 60), DateTime(2026, 10, 16));
    expect(livedDate(DateTime(2026, 10, 17, 5, 0), 5 * 60), DateTime(2026, 10, 17));
    expect(livedDate(DateTime(2026, 10, 17, 9, 0), 10 * 60), DateTime(2026, 10, 16)); // travail de nuit
    expect(livedYmd(DateTime(2026, 10, 17, 0, 30), 5 * 60), '20261016');
    expect(livedDate(DateTime(2026, 10, 17, 0, 30), 0), DateTime(2026, 10, 17)); // minuit = calendaire
  });

  test('livedProgramYmd : clé du programme de la journée vécue', () {
    expect(livedProgramYmd(DateTime(2026, 10, 17, 0, 30), 5 * 60), '2026-10-16');
    expect(livedProgramYmd(DateTime(2026, 10, 17, 6, 0), 5 * 60), '2026-10-17');
  });

  test('livedDayStart / livedNowMin', () {
    expect(livedDayStart(DateTime(2026, 10, 17, 0, 30), 5 * 60), DateTime(2026, 10, 16, 5));
    expect(livedDayStart(DateTime(2026, 10, 17, 23, 0), 5 * 60), DateTime(2026, 10, 17, 5));
    expect(livedNowMin(DateTime(2026, 10, 17, 0, 30), 5 * 60), 24 * 60 + 30);
    expect(livedNowMin(DateTime(2026, 10, 17, 7, 0), 5 * 60), 7 * 60);
  });

  test('parseDayStartMin : bornes et défaut ; dayStartLabel', () {
    expect(parseDayStartMin(null), kDefaultDayStartMin);
    expect(parseDayStartMin(600), 600);
    expect(parseDayStartMin(13 * 60), kDefaultDayStartMin);
    expect(parseDayStartMin(-1), kDefaultDayStartMin);
    expect(dayStartLabel(5 * 60), '5 h');
    expect(dayStartLabel(5 * 60 + 30), '5 h 30');
  });
}
