import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart';

void main() {
  testWidgets('showUndoSnackBar se ferme même en navigation accessible', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(accessibleNavigation: true),
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(onPressed: () => showUndoSnackBar(ctx, 'Étape supprimée', () {}), child: const Text('go')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Étape supprimée'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Étape supprimée'), findsNothing);
  });
}
