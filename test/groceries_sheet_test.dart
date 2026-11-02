import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/widgets/groceries_sheet.dart';

void main() {
  test('la liste fond le menu et les lignes à la main, par endroit', () {
    const g = Groceries(items: {
      '1': GroceryItem(id: '1', label: 'Ampoules', domainId: 'int', store: 'Bricolage'),
      '2': GroceryItem(id: '2', label: 'pâtes', domainId: 'int'),
    }, memory: {
      'tomates': GroceryMemory(store: 'Marché'),
    });
    final rows = groceryRows(
      menuLines: const [ShoppingLine('pâtes', 'Pâtes', '1 kg', ['Bolognaise']), ShoppingLine('tomates', 'Tomates', '4', ['Salade'])],
      menuChecked: {'tomates'},
      g: g,
      menuDomainId: 'sante',
    );
    expect(rows.length, 3); // « pâtes » à la main n'est pas doublé
    expect(rows.firstWhere((r) => r.label == 'Pâtes').domainId, 'sante');
    expect(rows.firstWhere((r) => r.label == 'Tomates').inBasket, isTrue);
    final by = rowsByStore(rows, kDefaultStores);
    expect(by.map((e) => e.key), ['Supermarché', 'Bricolage', 'Marché']);
    expect(checkoutLinesOf(rows, g).single.label, 'Tomates');
  });

  testWidgets('Courses : menu + à la main, cocher, ajouter un mot connu', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'int', name: 'Intendance')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final t = logic.livedToday;
    final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
    final bolo = Recipe(title: 'Bolognaise', portions: 2, ingredients: [ShoppingItem(label: 'Pâtes', qty: '500 g')]);
    await logic.setMeal(ymdOf(monday), mealKey(ymdOf(monday), 'soir'), PlannedMeal(recipeId: bolo.id, title: bolo.title, portions: 2));
    await logic.addGrocery(label: 'Ampoules', domainId: 'int', store: 'Bricolage');
    await logic.removeGrocery(logic.groceries.items.keys.single);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GroceriesSheet(logic: logic, sync: FirestoreSync(), recipes: Stream.value([bolo])))));
    await tester.pump();
    expect(find.text('Pâtes'), findsOneWidget);
    expect(find.text('pour Bolognaise'), findsOneWidget);
    expect(find.text('1 à prendre'), findsOneWidget);

    // « ampoules » est connu : ajout direct, au bon endroit.
    await tester.enterText(find.byType(TextField), 'ampoules');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('BRICOLAGE · 1'), findsOneWidget);
    expect(find.text('2 à prendre'), findsOneWidget);

    await tester.tap(find.text('Pâtes'));
    await tester.pump();
    expect(find.text('DANS LE PANIER · 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
