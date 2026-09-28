import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/week_planner.dart';

ScheduleBlock _b(String start, int dur) =>
    ScheduleBlock(startTime: start, durationMin: dur, title: 'b');

void main() {
  final today = DateTime(2026, 9, 28); // lundi
  final cap = {for (final k in ['mon', 'tue', 'wed', 'thu', 'fri']) k: 120, 'sat': 0, 'sun': 0};

  test('dayLoad : charge, capacité et « tient »', () {
    final l = dayLoad(today, [_b('08:00', 60)], cap, 45, today: today);
    expect(l.loadMin, 60);
    expect(l.capMin, 120);
    expect(l.fits, isTrue);
    // Capacité dépassée → ne tient pas.
    expect(dayLoad(today, [_b('08:00', 90)], cap, 45, today: today).fits, isFalse);
    // Jour de repos (capacité 0) → ne tient pas.
    expect(dayLoad(DateTime(2026, 10, 3), const [], cap, 45, today: today).fits, isFalse);
    // Jour passé → ne tient pas.
    expect(dayLoad(DateTime(2026, 9, 27), const [], cap, 45, today: today).fits, isFalse);
  });

  test('firstFittingDay : saute les jours pleins et le week-end', () {
    final days = [for (var i = 0; i < 10; i++) today.add(Duration(days: i))];
    final byDay = {
      ymdOf(today): [_b('08:00', 120)], // lundi plein
      ymdOf(today.add(const Duration(days: 1))): [_b('08:00', 100)], // mardi : 20 min restent
    };
    expect(firstFittingDay(days, byDay, cap, 45, today: today), DateTime(2026, 9, 30));
    expect(firstFittingDay(days, byDay, cap, 20, today: today), DateTime(2026, 9, 29));
    // Rien ne tient sur 10 jours pleins → null.
    final full = {for (final d in days) ymdOf(d): [_b('08:00', 120)]};
    expect(firstFittingDay(days, full, cap, 45, today: today), isNull);
  });
}
