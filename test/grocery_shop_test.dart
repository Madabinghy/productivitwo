import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/widgets/grocery_shop_screen.dart';

void main() {
  testWidgets('Caisse : total réparti par domaine, dépenses, liste vidée', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'sante', name: 'Santé'), Domain(id: 'int', name: 'Intendance')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final t = logic.livedToday;
    final monday = ymdOf(DateTime(t.year, t.month, t.day - (t.weekday - 1)));
    final bolo = Recipe(title: 'Bolognaise', portions: 2, ingredients: [ShoppingItem(label: 'Pâtes', qty: '500 g')]);
    await logic.setMeal(monday, mealKey(monday, 'soir'), PlannedMeal(recipeId: bolo.id, title: bolo.title, portions: 2));
    await logic.setShoppingChecked(monday, {'pâtes'});
    final x = await logic.addGrocery(label: 'Lessive', domainId: 'int');
    await logic.setGroceryInBasket(x.id, true);
    await logic.updateGrocery(logic.groceries.items[x.id]!);
    // La lessive a déjà un prix connu : 6 €.
    logic.groceries = logic.groceries.copyWith(memory: {...logic.groceries.memory, 'lessive': const GroceryMemory(domainId: 'int', price: 600)});

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GroceryCheckout(logic: logic, recipes: [bolo]))));
    expect(find.text('2 lignes dans le panier'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    // Pâtes : sans prix → moyenne (6 €) : 6 € / 6 €.
    expect(find.text('Santé'), findsOneWidget);
    expect(find.text('Intendance'), findsOneWidget);
    expect(find.text(euros(600)), findsNWidgets(2));
    await tester.tap(find.text('Enregistrer · 2 dépenses'));
    await tester.pumpAndSettle();
    expect(logic.finances.expenses.length, 2);
    expect(logic.groceries.items, isEmpty);
    expect(logic.groceries.boughtMenu[monday], {'pâtes'});
    final rows = groceryRows(menuLines: shoppingFor(logic.mealWeek(monday), [bolo]), menuChecked: logic.mealWeek(monday).checked, g: logic.groceries, monday: monday);
    expect(rows, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });
}
