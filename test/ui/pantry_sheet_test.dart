import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/pantry.dart';
import 'package:productivitwo_v1/widgets/pantry_sheet.dart';

void main() {
  testWidgets('Mes placards : par rayon, tap sur l\'état = suivant, ajout, rayon ajouté', (tester) async {
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    var g = afterPurchase(const Groceries(), ['Pâtes', 'Liquide vaisselle'], '2026-11-03');
    g = withPantryState(g, 'Riz', PantryState.low);
    logic.groceries = g;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PantrySheet(logic: logic))));
    await tester.pumpAndSettle();
    expect(find.text('3 produits'), findsOneWidget);
    expect(find.text('ÉPICERIE'), findsOneWidget);
    expect(find.text('MÉNAGER'), findsOneWidget);
    expect(find.textContaining('Achats du 3 nov.'), findsOneWidget);
    // Pâtes : J'en ai → Bientôt fini.
    await tester.tap(find.text('J\'en ai').first);
    await tester.pumpAndSettle();
    expect(logic.groceries.pantry['pâtes']!.state, PantryState.low);
    // Ajout d'un produit.
    await tester.enterText(find.byKey(const Key('pantry-add')), 'Bananes');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(logic.groceries.pantry['bananes']!.aisle, 'Fruits et légumes');
    expect(find.text('FRUITS ET LÉGUMES'), findsOneWidget);
    // Réglages d'un produit : rayon et habituel.
    await tester.tap(find.text('Riz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Produit habituel'));
    await tester.pumpAndSettle();
    expect(logic.groceries.pantry['riz']!.staple, isTrue);
    await tester.tap(find.text('Frais').last);
    await tester.pumpAndSettle();
    expect(logic.groceries.pantry['riz']!.aisle, 'Frais');
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rayons : ajouter avant Autre', (tester) async {
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showAislesSheet(c, logic: logic), child: const Text('go'))))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ajouter un rayon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un rayon'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bébé');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(logic.groceries.aisles.sublist(logic.groceries.aisles.length - 2), ['Bébé', 'Autre']);
    expect(find.text('Bébé'), findsOneWidget);
  });
}
