import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/dishes_sheet.dart';

void main() {
  testWidgets('Mes plats et la fiche d’un plat', (tester) async {
    tester.view.physicalSize = const Size(720, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final r = Recipe(title: 'Bolognaise', portions: 3, ingredients: [ShoppingItem(label: 'Pâtes', qty: '500 g')], timesCooked: 8, lastCookedAt: DateTime.now());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DishesSheet(sync: FirestoreSync(), recipes: Stream.value([r])))));
    await tester.pump();
    expect(find.text('LES PLUS FAITS'), findsOneWidget);
    expect(find.text('Bolognaise'), findsOneWidget);
    expect(find.text('×8'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DishSheet(sync: FirestoreSync(), recipe: r, all: [r]))));
    await tester.enterText(find.byType(TextField).last, '2 oignons, 1 kg riz');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Oignons'), findsOneWidget);
    expect(find.text('1 kg'), findsOneWidget);
    expect(find.text('pour 3 portions'), findsOneWidget);
  });
}
