import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/widgets/finance_sheet.dart';

void main() {
  testWidgets('Une dépense ancienne se supprime depuis sa feuille (Où va mon argent)', (tester) async {
    tester.view.physicalSize = const Size(780, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    const x = Expense(id: 'amende', ymd: '2020-01-02', amount: 13500, envelopeId: 'imprevus');
    logic.finances = const Finances().copyWith(expenses: {'amende': x});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => TextButton(onPressed: () => editExpense(ctx, logic: logic, expense: x), child: const Text('ouvrir'))),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer cette dépense'));
    await tester.pumpAndSettle();
    expect(logic.finances.expenses.containsKey('amende'), isFalse);
    expect(find.textContaining('retirés'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
