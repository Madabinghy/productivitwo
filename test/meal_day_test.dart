import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/meal_day.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';

void main() {
  test('la semaine des repas', () {
    final days = ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08'];
    final now = DateTime(2026, 11, 4, 18);
    final rep = Activity(id: 'r', domainId: 'd', name: 'Repas équilibré', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 2, createdAt: DateTime(2026));
    final manger = Activity(id: 'm', domainId: 'd', name: 'Manger', role: ActivityRole.generic, type: 'time', goalMin: 1, createdAt: DateTime(2026));
    final cuis = Activity(id: 'c', domainId: 'd', name: 'Cuisiner', role: ActivityRole.generic, type: 'time', goalMin: 1, createdAt: DateTime(2026));
    final hits = [HabitHit(habitId: 'r', ts: DateTime(2026, 11, 2, 12, 30)), HabitHit(habitId: 'r', ts: DateTime(2026, 11, 2, 20))];
    final sessions = [
      Session(activityId: 'm', startAt: DateTime(2026, 11, 3, 12, 0), endAt: DateTime(2026, 11, 3, 12, 30)),
      Session(activityId: 'c', startAt: DateTime(2026, 11, 3, 19, 0), endAt: DateTime(2026, 11, 3, 19, 40)),
    ];
    final week = MealWeek(slots: {mealKey('2026-11-04', 'soir'): const PlannedMeal(title: 'Chili')});
    final v = mealWeekView(days: days, week: week, activities: [rep, manger, cuis], hits: hits, sessions: sessions, now: now, dayStartMin: 0);
    expect(v.cells[mealKey('2026-11-02', 'midi')], MealCell.ok);
    expect(v.cells[mealKey('2026-11-03', 'midi')], MealCell.other);
    expect(v.cells[mealKey('2026-11-04', 'midi')], MealCell.none);
    expect(v.cells[mealKey('2026-11-04', 'soir')], MealCell.planned);
    expect(v.balanced, 2);
    expect(v.counted, 5);
    expect(v.skippedLunches, 1);
    expect(v.cookMin, 40);
    expect(v.lunchClock, 12 * 60);
  });
}
