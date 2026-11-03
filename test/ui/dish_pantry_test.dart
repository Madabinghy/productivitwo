import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/pantry.dart';
import 'package:productivitwo_v1/widgets/dishes_sheet.dart';

void main() {
  testWidgets('plats face au placard : avec ce que tu as, ce qui manque à la liste', (tester) async {
    tester.view.physicalSize = const Size(720, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    var g = afterPurchase(const Groceries(), ['Pâtes', 'Oignons', 'Thon'], '2026-11-03');
    g = withPantryState(g, 'Bœuf haché', PantryState.out);
    logic.groceries = g;
    final bolo = Recipe(title: 'Bolognaise', ingredients: [ShoppingItem(label: 'Pâtes', qty: '500 g'), ShoppingItem(label: 'Oignons', qty: '2'), ShoppingItem(label: 'Bœuf haché', qty: '500 g')]);
    final thon = Recipe(title: 'Pâtes au thon', ingredients: [ShoppingItem(label: 'Pâtes'), ShoppingItem(label: 'Thon')]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DishesSheet(sync: FirestoreSync(), recipes: Stream.value([bolo, thon]), logic: logic))));
    await tester.pump();
    expect(find.text('AVEC CE QUE TU AS'), findsOneWidget);
    expect(find.text('tous les ingrédients au placard'), findsOneWidget);
    expect(find.text('il manque Bœuf haché'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DishSheet(sync: FirestoreSync(), recipe: bolo, all: [bolo], logic: logic))));
    await tester.pump();
    expect(find.text('✓'), findsNWidgets(2));
    expect(find.text('✕'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dish-add-missing')));
    await tester.pump();
    expect(logic.groceries.items.values.single.label, 'Bœuf haché');
    expect(find.text('Ce qui manque est déjà sur la liste de courses.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
