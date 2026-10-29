import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routines_today.dart';

void main() {
  // Jeudi 29 oct. 2026, 19 h ; la journée commence à 5 h.
  final now = DateTime(2026, 10, 29, 19);
  HabitHit hit(String id, DateTime ts) => HabitHit(habitId: id, ts: ts);

  test('quotidienne : cible × 7, attendu = cible × jours écoulés', () {
    final a = Activity(id: 'p', name: 'Pompes', domainId: 's', role: ActivityRole.generic, type: 'habit', goalMin: 1, createdAt: DateTime(2026, 1, 1), habitFreq: HabitFreq.daily, habitTarget: 20);
    final hits = [
      hit('p', DateTime(2026, 10, 25, 22)), // dimanche : semaine d'avant
      hit('p', DateTime(2026, 10, 26, 3)), // lundi 3 h : encore la journée de dimanche
      hit('p', DateTime(2026, 10, 26, 8)),
      hit('p', DateTime(2026, 10, 29, 7)),
      hit('x', DateTime(2026, 10, 29, 7)),
    ];
    final w = routineCalendarWeek(a, hits, now, 300)!;
    expect(w.done, 2);
    expect(w.total, 140);
    expect(w.expected, 80);
  });

  test('hebdo : cible de la semaine, attendu au prorata ; mensuelle : rien', () {
    final a = Activity(id: 'f', name: 'Footing', domainId: 's', role: ActivityRole.generic, type: 'habit', goalMin: 1, createdAt: DateTime(2026, 1, 1), habitFreq: HabitFreq.weekly, habitTarget: 3);
    final w = routineCalendarWeek(a, const [], now, 300)!;
    expect(w.total, 3);
    expect(w.expected, 2);
    final m = Activity(id: 'm', name: 'Budget', domainId: 's', role: ActivityRole.generic, type: 'habit', goalMin: 1, createdAt: DateTime(2026, 1, 1), habitFreq: HabitFreq.monthly, habitTarget: 1);
    expect(routineCalendarWeek(m, const [], now, 300), isNull);
  });
}
