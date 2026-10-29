import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/rest_sheet.dart';

/// Veille des domaines : avec beaucoup de domaines sur un petit écran, la
/// liste défile et le bouton de validation reste visible.
void main() {
  testWidgets('feuille de veille : boutons visibles, liste défilante', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [for (var i = 0; i < 14; i++) Domain(id: 'd$i', name: 'Domaine $i')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {});
    int? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await showRestSheet(ctx, logic: logic, sync: FirestoreSync(), untilYmd: '2026-10-29', title: 'Deep work lancé · mettre le reste en veille jusqu\'à ce soir ?'),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Pas de veille'), findsOneWidget);
    await tester.tap(find.text('Domaine 0'));
    await tester.pump();
    expect(find.text('Mettre en veille · 1').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Pas de veille'));
    await tester.pumpAndSettle();
    expect(find.text('Domaine 0'), findsNothing);
    expect(result, 0);
  });
}
