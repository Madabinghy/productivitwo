import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';

void main() {
  test('retirer des restes : une portion de moins, les autres remontent', () {
    const days = ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08'];
    final slots = {mealKey(days[0], 'soir'): const PlannedMeal(title: 'Ribs', portions: 3)};
    final left = leftoversOf(slots, days);
    expect(left.keys, [mealKey(days[1], 'midi'), mealKey(days[2], 'midi')]);
    // Retirer les restes du mercredi : il n'en reste qu'au mardi, rien ne part jeudi.
    final r = removeLeftoverAt(slots, days, mealKey(days[2], 'midi'))!;
    expect(r.portions, 2);
    final after = {...slots, r.sourceKey: const PlannedMeal(title: 'Ribs', portions: 2)};
    expect(leftoversOf(after, days).keys, [mealKey(days[1], 'midi')]);
    // Un « Dehors » mardi vidé : les restes remontent au mardi.
    final blocked = {...slots, mealKey(days[1], 'midi'): const PlannedMeal(title: 'Dehors', out: true)};
    expect(leftoversOf(blocked, days).keys, [mealKey(days[2], 'midi'), mealKey(days[3], 'midi')]);
    expect(removeLeftoverAt(slots, days, mealKey(days[1], 'soir')), isNull);
  });

  test('des restes notés « mangés » consomment leur portion, sans pousser les autres', () {
    const days = ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08'];
    final slots = {
      mealKey(days[0], 'soir'): const PlannedMeal(title: 'Ribs', portions: 3),
      mealKey(days[1], 'midi'): const PlannedMeal(title: '${kLeftoverPrefix}Ribs', noted: true).withAte('ok'),
    };
    expect(leftoversOf(slots, days).keys, [mealKey(days[1], 'midi'), mealKey(days[2], 'midi')]);
    // Effacer un repas noté sur un plat prévu le remet « prévu », ce qu'on a mangé part avec.
    final p = const PlannedMeal(title: 'Pâtes', portions: 2).withAte('other', what: 'Kebab');
    expect(p.ateWhat, 'Kebab');
    final cleared = p.withAte(null);
    expect(cleared.ate, isNull);
    expect(cleared.ateWhat, isNull);
    expect(PlannedMeal.from(p.toJson())!.ateWhat, 'Kebab');
  });
}
