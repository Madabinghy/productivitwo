import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/tile_charts.dart';

Activity routine(String id, String name, {HabitFreq freq = HabitFreq.daily, int target = 1}) =>
    Activity(id: id, domainId: 'd', name: name, type: 'habit', habitFreq: freq, habitTarget: target);

void main() {
  test('cumul : fait face à l\'attendu, libellé de l\'écart', () {
    final c = cumulChart([250, 295, 275, 220], perDay: 252, windowDays: 7);
    expect(c.cumul, [250, 545, 820, 1040]);
    expect(c.expected, 1008);
    expect(cumulLabel(c, (m) => '$m min'), '+32 min sur le rythme');
    expect(cumulLabel(cumulChart([10], perDay: 0, windowDays: 7), (m) => '$m'), 'cette semaine');
    expect(c.scaleMax, 252 * 7);
  });

  test('calendrier : niveaux face au minimum, sinon au meilleur jour', () {
    expect(calendarLevels([0, 5, 15, 25, 40], goal: 20), [0, 1, 2, 3, 4]);
    expect(calendarLevels([0, 10, 100]), [0, 1, 4]);
    expect(activeDays([0, 3, 0, 1]), 2);
  });

  test('routines × jours : quotidienne, hebdo, celles qui décrochent d\'abord', () {
    final now = DateTime(2026, 11, 5, 18); // jeudi
    final lit = routine('lit', 'Faire mon lit');
    final lessive = routine('lessive', 'Lessive', freq: HabitFreq.weekly, target: 3);
    final voiture = routine('voiture', 'Laver la voiture', freq: HabitFreq.monthly);
    final hits = [
      for (var d = 2; d <= 5; d++) HabitHit(habitId: 'lit', ts: DateTime(2026, 11, d, 8)),
      HabitHit(habitId: 'lessive', ts: DateTime(2026, 11, 3, 10)),
    ];
    final rows = routineGrid(routines: [lit, lessive, voiture], hits: hits, now: now, dayStartMin: 300);
    expect(rows.map((r) => r.routine.id), ['lit', 'lessive']); // mensuelle exclue ; personne en retard : par nom
    final l = rows.firstWhere((r) => r.routine.id == 'lit');
    expect(l.right, '4/4');
    expect(l.behind, isFalse);
    expect(l.cells.sublist(4), everyElement(RoutineCell.future));
    final w = rows.firstWhere((r) => r.routine.id == 'lessive');
    expect(w.right, '1/3');
    expect(w.behind, isFalse); // 3 × 3 / 7 = 1 attendu à jeudi
    expect(w.cells[1], RoutineCell.done);
    // Un jour passé manqué : la quotidienne décroche.
    final rows2 = routineGrid(routines: [lit], hits: hits.where((h) => h.ts.day != 3).toList(), now: now, dayStartMin: 300);
    expect(rows2.single.behind, isTrue);
    expect(rows2.single.right, '3/4');
  });
}
