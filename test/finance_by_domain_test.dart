import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/widgets/finance_sheet.dart';

void main() {
  testWidgets('Finances : ce mois par domaine de vie et par projet', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'sante', name: 'Santé'), Domain(id: 'int', name: 'Intendance')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await logic.logExpense(amount: 4120, envelopeId: 'courses', domainId: 'sante');
    await logic.logExpense(amount: 770, envelopeId: 'courses', domainId: 'int', projectId: 'p');
    await logic.logExpense(amount: 500, envelopeId: 'sorties');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FinanceSheet(logic: logic))));
    expect(find.text('CE MOIS · PAR DOMAINE DE VIE'), findsOneWidget);
    expect(find.text(euros(5390)), findsOneWidget);
    expect(find.text('Sans domaine'), findsOneWidget);
    expect(find.text('PROJETS CE MOIS'), findsOneWidget);
    expect(find.text('Liste de courses ›'), findsOneWidget);
  });
}
