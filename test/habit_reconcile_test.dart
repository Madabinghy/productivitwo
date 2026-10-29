import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/habit_reconcile.dart';

void main() {
  test('compteur et hits alignés sur le plus grand, idempotent', () {
    final now = DateTime(2026, 10, 29, 15);
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: [
      HabitProgress(activityId: 'eau', yyyymmdd: '20261029', value: 9),
    ], habitHits: [
      for (var i = 0; i < 4; i++) HabitHit(habitId: 'eau', ts: DateTime(2026, 10, 29, 8 + i)),
      HabitHit(habitId: 'lecture', ts: DateTime(2026, 10, 28, 21)),
    ]);
    final n = reconcileHabitStores(st, dayStartMin: 300, now: now);
    expect(st.habitHits.where((h) => h.habitId == 'eau').length, 9);
    expect(st.habitProgress.firstWhere((h) => h.activityId == 'lecture').value, 1);
    expect(n, 6);
    expect(reconcileHabitStores(st, dayStartMin: 300, now: now), 0);
  });
}
