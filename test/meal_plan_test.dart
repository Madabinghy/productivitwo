import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';

void main() {
  final days = ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08'];
  final bolo = Recipe(title: 'Bolognaise', portions: 3, ingredients: [ShoppingItem(label: 'Pâtes', qty: '500 g'), ShoppingItem(label: 'Oignon', qty: '1')]);
  final thon = Recipe(title: 'Pâtes au thon', portions: 1, ingredients: [ShoppingItem(label: 'pâtes', qty: '500 g'), ShoppingItem(label: 'Thon', qty: '1 boîte')]);

  test('restes sur les midis suivants', () {
    final slots = {
      mealKey('2026-11-04', 'soir'): PlannedMeal(recipeId: bolo.id, title: 'Bolognaise', portions: 3),
      mealKey('2026-11-06', 'midi'): const PlannedMeal(title: 'Dehors', out: true),
    };
    final l = leftoversOf(slots, days);
    expect(l[mealKey('2026-11-05', 'midi')], mealKey('2026-11-04', 'soir'));
    expect(l.containsKey(mealKey('2026-11-06', 'midi')), isFalse);
    expect(l[mealKey('2026-11-07', 'midi')], mealKey('2026-11-04', 'soir'));
  });

  test('liste de courses additionnée avec provenance', () {
    final week = MealWeek(slots: {
      mealKey('2026-11-04', 'soir'): PlannedMeal(recipeId: bolo.id, title: 'Bolognaise', portions: 3),
      mealKey('2026-11-03', 'soir'): PlannedMeal(recipeId: thon.id, title: 'Pâtes au thon'),
    }, extra: [ShoppingItem(label: 'Lessive')]);
    final lines = shoppingFor(week, [bolo, thon]);
    final pates = lines.firstWhere((l) => l.key == 'pâtes');
    expect(pates.qty, '1 kg');
    expect(pates.from, containsAll(['Bolognaise', 'Pâtes au thon']));
    expect(lines.last.manual, isTrue);
    expect(sumQty(['500 g', '1 boîte']), '500 g + 1 boîte');
    expect(sumQty(['2', '1']), '3');
    final parsed = parseMeals({
      'plans': {'2026-11-02': {mealKey('2026-11-04', 'soir'): PlannedMeal(title: 'X', portions: 2).toJson()}},
      'shopping': {'2026-11-02': {'checked': ['pâtes'], 'extra': [{'label': 'Lessive', 'qty': ''}]}},
    });
    expect(parsed['2026-11-02']!.slots.length, 1);
    expect(parsed['2026-11-02']!.checked, {'pâtes'});
  });
}
