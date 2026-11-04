import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/meal_families.dart';
import 'package:productivitwo_v1/utils/pantry.dart';
import 'package:productivitwo_v1/widgets/pantry_sheet.dart';

void main() {
  testWidgets('Mes placards par famille : compteurs, filtre, famille réglée dans l\'éditeur', (tester) async {
    tester.view.physicalSize = const Size(780, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    logic.groceries = afterPurchase(const Groceries(), ['Lardons', 'Riz', 'Pâtes', 'Liquide vaisselle', 'Tartelettes fraise'], '2026-11-04');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PantrySheet(logic: logic))));
    await tester.pumpAndSettle();
    // Protéines 1 · Féculents 2 · Fibres 0 (plus rien).
    expect(find.descendant(of: find.byKey(Key('pantry-family-$kFeculents')), matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: find.byKey(Key('pantry-family-$kFibres')), matching: find.text('plus rien')), findsOneWidget);
    // Filtre Féculents : Lardons disparaît.
    await tester.tap(find.byKey(Key('pantry-family-$kFeculents')));
    await tester.pumpAndSettle();
    expect(find.text('Lardons'), findsNothing);
    expect(find.text('Riz'), findsOneWidget);
    await tester.tap(find.byKey(Key('pantry-family-$kFeculents')));
    await tester.pumpAndSettle();
    // Éditeur : Tartelettes (accompagnement) → Fibres.
    await tester.tap(find.text('Tartelettes fraise'));
    await tester.pumpAndSettle();
    expect(find.text('FAMILLE POUR LES REPAS'), findsOneWidget);
    expect(find.text('Auto · Accompagnements'), findsOneWidget);
    await tester.tap(find.text('Fibres').last);
    await tester.pumpAndSettle();
    expect(logic.groceries.families['tartelettes fraise'], kFibres);
    expect(familiesFor(logic.groceries, 'Tartelettes fraise'), [kFibres]);
  });
}
