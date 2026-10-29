import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

/// Un « +3 » du compteur laisse trois traces (hits) : le compte du jour vécu,
/// les séries et les badges lisent les hits.
void main() {
  test('incHabit : une trace par unité, le −1 en retire une', () {
    final eau = Activity(
        id: 'eau', domainId: 'd', name: 'Boire de l\'eau', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 6, createdAt: DateTime(2026, 1, 1));
    final st = AppState(domains: [Domain(id: 'd', name: 'Santé')], activities: [eau], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final day = logic.livedToday;
    logic.incHabit('eau', 3, day);
    expect(st.habitHits.where((h) => h.habitId == 'eau').length, 3);
    expect(logic.habitValueOn('eau', day), 3);
    logic.incHabit('eau', -1, day);
    expect(st.habitHits.where((h) => h.habitId == 'eau').length, 2);
    expect(logic.habitValueOn('eau', day), 2);
  });
}
