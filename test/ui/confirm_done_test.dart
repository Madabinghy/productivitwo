import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/widgets/confirm_done.dart';

void main() {
  testWidgets('confirmDone : Annuler = false, « Oui, c\'est fait » = true', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(onPressed: () async => result = await confirmDone(ctx, title: 'Remplir la fiche'), child: const Text('go')),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Action faite ?'), findsOneWidget);
    expect(find.text('« Remplir la fiche »'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Oui, c'est fait"));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
