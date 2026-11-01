import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/meals.dart';

void main() {
  test('lecture d’une ligne d’ingrédient', () {
    String f(String s) {
      final i = parseIngredientLine(s);
      return '${i.label}|${i.qty}';
    }

    expect(f('2 oignons'), 'Oignons|2');
    expect(f('1 kg pâtes'), 'Pâtes|1 kg');
    expect(f('500 g de bœuf haché'), 'Bœuf haché|500 g');
    expect(f('Bœuf haché 500 g'), 'Bœuf haché|500 g');
    expect(f('Tomates concassées 2 boîtes'), 'Tomates concassées|2 boîtes');
    expect(f('sel'), 'Sel|');
    expect(parseIngredients('2 oignons, 1 kg pâtes').length, 2);
  });

  test('suggestions et tri des plats', () {
    final now = DateTime(2026, 11, 1);
    final a = Recipe(title: 'Bolognaise', ingredients: [ShoppingItem(label: 'Oignon'), ShoppingItem(label: 'Pâtes')], timesCooked: 8, lastCookedAt: now.subtract(const Duration(days: 3)));
    final b = Recipe(title: 'Chili', ingredients: [ShoppingItem(label: 'oignon'), ShoppingItem(label: 'Haricots')], timesCooked: 4, lastCookedAt: now.subtract(const Duration(days: 30)));
    final c = Recipe(title: 'Omelette', timesCooked: 0);
    expect(ingredientSuggestions([a, b], [ShoppingItem(label: 'Pâtes')]).first, 'Oignon');
    final s = sortDishes([a, b, c], now);
    expect(s.often.map((r) => r.title), ['Bolognaise']);
    expect(s.stale.map((r) => r.title), ['Chili']);
    expect(s.fresh.map((r) => r.title), ['Omelette']);
    expect(Recipe.from(Recipe(title: 'x', portions: 3, minutes: 50).toJson()).portions, 3);
  });
}
