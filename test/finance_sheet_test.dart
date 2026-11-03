import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/widgets/finance_sheet.dart';

void main() {
  testWidgets('Finances : rien dépensé, une dépense, reste à vivre', (tester) async {
    tester.view.physicalSize = const Size(800, 5000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final r = Activity(id: 'b', domainId: 'd', name: 'Suivre mon budget', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
    final st = AppState(domains: [], activities: [r], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FinanceSheet(logic: logic))));
    expect(find.text('Rien noté aujourd’hui.'), findsOneWidget);
    expect(find.text('Courses'), findsOneWidget);

    await tester.tap(find.text('✓ Rien dépensé'));
    await tester.pump();
    expect(find.text('✓ Rien dépensé aujourd’hui'), findsOneWidget);
    expect(st.habitHits.where((h) => h.habitId == 'b').length, 1);

    await logic.saveRecurring(const [Recurring(id: 's', name: 'Salaire', amount: 200000, income: true), Recurring(id: 'l', name: 'Loyer', amount: 65000)]);
    await logic.logExpense(amount: 2340, envelopeId: 'courses', note: 'Lidl');
    await tester.pump();
    expect(find.text('Rien noté aujourd’hui.'), findsNothing);
    expect(find.text('✓ Rien dépensé aujourd’hui'), findsNothing);
    expect(find.text(euros(200000 - 65000 - 2340)), findsOneWidget);
    expect(st.habitHits.where((h) => h.habitId == 'b').length, 1);

    await tester.tap(find.text('+ Dépense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12,5');
    await tester.pump();
    expect(find.text('Noter · 12,50 € Courses'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Finances : toucher une dépense la corrige, ou la supprime', (tester) async {
    tester.view.physicalSize = const Size(800, 5000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final id = (await logic.logExpense(amount: 2340, envelopeId: 'courses', note: 'Lidl'))!;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FinanceSheet(logic: logic))));
    await tester.tap(find.textContaining('Lidl'));
    await tester.pumpAndSettle();
    expect(find.text('Corriger la dépense'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '20');
    await tester.pump();
    await tester.tap(find.textContaining('Enregistrer ·'));
    await tester.pumpAndSettle();
    expect(logic.finances.expenses[id]!.amount, 2000);
    expect(logic.finances.expenses[id]!.note, 'Lidl');

    await tester.tap(find.textContaining('Lidl'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer cette dépense'));
    await tester.pumpAndSettle();
    expect(logic.finances.expenses, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(SnackBarAction, 'Annuler'));
    await tester.pump();
    expect(logic.finances.expenses[id]!.amount, 2000);
    await tester.pump(const Duration(seconds: 5));
  });
}
