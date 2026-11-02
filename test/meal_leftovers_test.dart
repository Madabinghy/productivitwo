import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';

void main() {
  test('plus de restes ici : le plat garde juste les restes d\'avant', () {
    const days = ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08'];
    final slots = {
      mealKey(days[0], 'soir'): const PlannedMeal(title: 'Ribs', portions: 3),
      mealKey(days[1], 'midi'): const PlannedMeal(title: 'Dehors', out: true),
      mealKey(days[2], 'midi'): const PlannedMeal(title: 'Dehors', out: true),
      mealKey(days[4], 'midi'): const PlannedMeal(title: 'OFF', portions: 1),
    };
    final left = leftoversOf(slots, days);
    expect(left[mealKey(days[3], 'midi')], mealKey(days[0], 'soir'));
    expect(left[mealKey(days[5], 'midi')], mealKey(days[0], 'soir'));
    final stop = stopLeftoversAt(slots, days, mealKey(days[5], 'midi'))!;
    expect(stop.sourceKey, mealKey(days[0], 'soir'));
    expect(stop.portions, 2); // le jeudi garde ses restes, plus rien samedi
    final after = {...slots, stop.sourceKey: const PlannedMeal(title: 'Ribs', portions: 2)};
    expect(leftoversOf(after, days).containsKey(mealKey(days[5], 'midi')), isFalse);
    expect(stopLeftoversAt(slots, days, mealKey(days[1], 'soir')), isNull);
  });
}
