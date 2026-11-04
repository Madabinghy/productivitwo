import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

void main() {
  test('« Pas aujourd\'hui » : la routine écartée ne casse plus la journée parfaite', () {
    final r = Activity(id: 'r', name: 'Pompes', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
    final day = DateTime(2026, 11, 1);
    final missed = scoreDay(day, activities: [r], reachedDaysByRoutine: const {});
    expect(missed.routinesDue, 1);
    final excused = scoreDay(day, activities: [r], reachedDaysByRoutine: const {}, excused: {'r'});
    expect(excused.routinesDue, 0);
    expect(excused.excused, 1);
  });
}
