import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/widgets/balance_check_sheet.dart';

void main() {
  testWidgets('Point de la semaine : premier solde, puis écart et oubli noté', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BalanceCheckSheet(logic: logic))));
    expect(find.text('Ton compte dit ?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1000');
    await tester.pump();
    await tester.tap(find.text('Comparer'));
    await tester.pump();
    expect(logic.finances.checks.values.single, 100000);
    expect(find.text('Le prochain point partira de là.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    // Une semaine plus tard (le point précédent recule de 7 jours).
    final last = prevYmd(prevYmd(prevYmd(prevYmd(prevYmd(prevYmd(prevYmd(logic.livedTodayYmd)))))));
    logic.finances = logic.finances.copyWith(checks: {last: 100000});
    await logic.logExpense(amount: 20000, envelopeId: 'courses');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BalanceCheckSheet(key: UniqueKey(), logic: logic))));
    await tester.enterText(find.byType(TextField), '760');
    await tester.pump();
    await tester.tap(find.text('Comparer'));
    await tester.pump();
    expect(find.text(euros(80000)), findsOneWidget);
    expect(find.text('Noter 40 € oubliés'), findsOneWidget);
    await tester.tap(find.text('Noter 40 € oubliés'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imprévus'));
    await tester.pumpAndSettle();
    expect(logic.finances.expenses.values.where((x) => x.amount == 4000 && x.envelopeId == 'imprevus').length, 1);
    expect(logic.finances.checks[logic.livedTodayYmd], 76000);
    await tester.pump(const Duration(seconds: 4));
  });
}
