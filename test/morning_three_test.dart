import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/morning_three.dart';

void main() {
  test('fenêtre du matin : 5 h → 9 h', () {
    expect(isMorningWindow(DateTime(2026, 10, 2, 7, 30)), isTrue);
    expect(isMorningWindow(DateTime(2026, 10, 2, 9)), isFalse);
    expect(isMorningWindow(DateTime(2026, 10, 2, 4, 59)), isFalse);
  });

  test('bloc clé : le plus long bloc projet à faire, sinon le plus long tout court', () {
    final blocks = [
      ScheduleBlock(startTime: '08:00', durationMin: 30, title: 'Routine', category: 'routine'),
      ScheduleBlock(startTime: '09:00', durationMin: 120, title: 'Offre', category: 'project', projectId: 'p'),
      ScheduleBlock(startTime: '14:00', durationMin: 240, title: 'Fait', category: 'project', status: 'done'),
      ScheduleBlock(startTime: '16:00', durationMin: 60, title: 'Relance', category: 'project'),
    ];
    expect(keyBlockOf(blocks)?.title, 'Offre');
    expect(keyBlockOf([blocks.first])?.title, 'Routine');
    expect(keyBlockOf([]), isNull);
  });

  test('routine la plus en retard sur la semaine, hors atteintes du jour', () {
    final a = Activity(id: 'a', name: 'Pompes', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 10);
    final b = Activity(id: 'b', name: 'Eau', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 6);
    final c = Activity(id: 'c', name: 'Lecture', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);
    final done = {'a': 60, 'b': 10, 'c': 0};
    final r = laggingRoutineOf([a, b, c],
        weekDone: (x) => done[x.id]!,
        weekTarget: (x) => (x.habitTarget ?? 1) * 7,
        reachedToday: (x) => x.id == 'c');
    expect(r?.id, 'b');
  });

  test('action en retard la plus ancienne, projets actifs seulement', () {
    final d0 = DateTime(2026, 10, 2);
    final p1 = Project(id: 'p1', title: 'A', startDate: d0, createdBy: 'u', tasks: [
      ProjectTask(id: 't1', title: 'Facture', startDate: d0, endDate: DateTime(2026, 9, 28)),
      ProjectTask(id: 't2', title: 'Faite', startDate: d0, endDate: DateTime(2026, 9, 20), status: 'done'),
    ]);
    final p2 = Project(id: 'p2', title: 'B', startDate: d0, createdBy: 'u', paused: true, tasks: [
      ProjectTask(id: 't3', title: 'Pause', startDate: d0, endDate: DateTime(2026, 9, 1)),
    ]);
    expect(oldestOverdueOf([p1, p2], d0)?.task.id, 't1');
    expect(oldestOverdueOf([p2], d0), isNull);
  });
}
